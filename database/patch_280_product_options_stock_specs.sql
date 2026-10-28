-- ============================================================================
--  patch_280 — product options (sizes/colours), stock, specifications;
--              checkout checks and deducts stock; orders only via checkout
--  STATUS: APPLIED to the live database 28 Oct 2026 (owner approved).
-- ============================================================================
--
--  Owner, 28 Oct 2026: "start with product sizes stock specs".
--
--  1. products.stock_quantity — optional. NULL = the seller doesn't count
--     stock (still the default; nothing changes for existing listings).
--     products.option_groups — up to 2 groups, e.g.
--       [{"name":"Size","values":["S","M","L"]},{"name":"Colour","values":[…]}]
--     products.specs — up to 20 {"label","value"} rows ("Material: Leather").
--
--  2. product_variants — one row per combination ("M / Black") with its own
--     optional stock and optional price. Readable wherever the product is
--     readable; only the product's seller can write them. When every
--     active variant counts stock, products.stock_quantity is kept as their
--     total (so cards can say "Sold out" without loading variants).
--
--  3. place_order (same signature, so the app keeps working): lines may
--     carry variant_id; the product and variant rows are LOCKED, a product
--     with options must name one, quantity can't exceed stock, the price
--     is the variant's own when set, and stock is deducted in the same
--     transaction. Two buyers can't both get the last one.
--     Cancelling an order puts its stock back.
--     order_items gains variant_id + variant_label (a snapshot).
--
--  4. BUG — checkout has never worked. place_order called
--     jsonb_array_length(p.image_urls), but image_urls is text[], so every
--     order failed with "function jsonb_array_length(text[]) does not
--     exist". That is why the live database had 0 orders. Fixed here
--     (image_urls[1]); found by rehearsing this patch on the live DB.
--
--  5. SECURITY (found while reading the order rules): `authenticated`
--     could INSERT straight into orders and order_items — any seller, any
--     status, any price — bypassing place_order's server pricing (and now
--     stock). The app never does this (it always calls place_order, which
--     is SECURITY DEFINER), so direct inserts are revoked. Live data had
--     0 orders, so nothing was abused.
--
--  CLAUDE.md: BEFORE triggers return COALESCE(NEW, OLD). Not `profiles`.
-- ============================================================================

BEGIN;

-- 1. Product columns -------------------------------------------------------------
ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS stock_quantity integer,
  ADD COLUMN IF NOT EXISTS option_groups jsonb NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS specs jsonb NOT NULL DEFAULT '[]'::jsonb;

ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_stock_check;
ALTER TABLE public.products ADD CONSTRAINT products_stock_check
  CHECK (stock_quantity IS NULL OR stock_quantity BETWEEN 0 AND 100000);
ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_option_groups_check;
ALTER TABLE public.products ADD CONSTRAINT products_option_groups_check
  CHECK (jsonb_typeof(option_groups) = 'array'
         AND jsonb_array_length(option_groups) <= 2
         AND pg_column_size(option_groups) <= 4000);
ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_specs_check;
ALTER TABLE public.products ADD CONSTRAINT products_specs_check
  CHECK (jsonb_typeof(specs) = 'array'
         AND jsonb_array_length(specs) <= 20
         AND pg_column_size(specs) <= 8000);

-- 2. Variants -----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.product_variants (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  product_id bigint NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  options    jsonb  NOT NULL DEFAULT '{}'::jsonb
             CHECK (jsonb_typeof(options) = 'object'),
  label      text   NOT NULL CHECK (length(btrim(label)) BETWEEN 1 AND 80),
  price      numeric(12,2) CHECK (price IS NULL OR price > 0),
  stock      integer CHECK (stock IS NULL OR stock BETWEEN 0 AND 100000),
  sort       smallint NOT NULL DEFAULT 0,
  is_active  boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (product_id, label)
);
CREATE INDEX IF NOT EXISTS product_variants_product
  ON public.product_variants (product_id, sort);

ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS product_variants_read ON public.product_variants;
CREATE POLICY product_variants_read ON public.product_variants FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.products p WHERE p.id = product_id));

DROP POLICY IF EXISTS product_variants_write ON public.product_variants;
CREATE POLICY product_variants_write ON public.product_variants FOR ALL
  USING (EXISTS (SELECT 1 FROM public.products p
                  WHERE p.id = product_id AND p.seller_id = auth.uid())
         AND public.user_is_active())
  WITH CHECK (EXISTS (SELECT 1 FROM public.products p
                       WHERE p.id = product_id AND p.seller_id = auth.uid())
              AND public.user_is_active());

REVOKE ALL ON public.product_variants FROM anon, authenticated;
GRANT SELECT ON public.product_variants TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.product_variants TO authenticated;

CREATE OR REPLACE FUNCTION public.product_variants_limit()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  IF (SELECT count(*) FROM product_variants WHERE product_id = NEW.product_id) >= 50 THEN
    RAISE EXCEPTION 'A product can have up to 50 option combinations.'
      USING ERRCODE = 'P0001';
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$function$;
DROP TRIGGER IF EXISTS product_variants_limit_trg ON public.product_variants;
CREATE TRIGGER product_variants_limit_trg BEFORE INSERT ON public.product_variants
  FOR EACH ROW EXECUTE FUNCTION public.product_variants_limit();

-- Keep products.stock_quantity = the variants' total when every active
-- variant counts stock; NULL when any doesn't (stock isn't tracked).
CREATE OR REPLACE FUNCTION public.product_variants_sync_stock()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_pid bigint := COALESCE(NEW.product_id, OLD.product_id);
  v_active int;
  v_untracked int;
  v_total int;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE stock IS NULL), COALESCE(sum(stock), 0)
    INTO v_active, v_untracked, v_total
    FROM product_variants WHERE product_id = v_pid AND is_active;
  IF v_active > 0 THEN
    UPDATE products
       SET stock_quantity = CASE WHEN v_untracked > 0 THEN NULL ELSE v_total END
     WHERE id = v_pid
       AND stock_quantity IS DISTINCT FROM
           (CASE WHEN v_untracked > 0 THEN NULL ELSE v_total END);
  END IF;
  RETURN NULL;
END;
$function$;
DROP TRIGGER IF EXISTS product_variants_sync_stock_trg ON public.product_variants;
CREATE TRIGGER product_variants_sync_stock_trg
  AFTER INSERT OR UPDATE OR DELETE ON public.product_variants
  FOR EACH ROW EXECUTE FUNCTION public.product_variants_sync_stock();

-- 3. Order lines remember the option ---------------------------------------------
ALTER TABLE public.order_items
  ADD COLUMN IF NOT EXISTS variant_id bigint
    REFERENCES public.product_variants(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS variant_label text;

CREATE OR REPLACE FUNCTION public.place_order(
  p_seller_id uuid, p_items jsonb, p_note text DEFAULT NULL::text,
  p_buyer_name text DEFAULT NULL::text, p_buyer_phone text DEFAULT NULL::text)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare
  v_buyer      uuid := auth.uid();
  v_order_id   bigint;
  v_currency   text;
  v_subtotal   numeric(12,2);
  v_item_count integer;
  v_valid      integer;
  v_requested  integer;
  v_bad        record;
begin
  if v_buyer is null then
    raise exception 'not signed in';
  end if;
  if not user_is_active() then
    raise exception 'account is not active';
  end if;
  if p_seller_id = v_buyer then
    raise exception 'cannot order from your own store';
  end if;
  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'no items';
  end if;

  -- Scratch tables live until commit; clear any from an earlier call in
  -- the same transaction.
  drop table if exists pg_temp._req;
  drop table if exists pg_temp._lines;

  -- One request line per product + option (repeats are added together).
  create temp table _req on commit drop as
  select (i->>'product_id')::bigint                        as product_id,
         nullif(i->>'variant_id', '')::bigint              as variant_id,
         least(sum(greatest(coalesce((i->>'qty')::int, 1), 1)), 99)::int as qty
    from jsonb_array_elements(p_items) as i
   group by 1, 2;

  -- Lock what we are about to check and deduct, so two checkouts can't
  -- both take the last one.
  perform 1 from products
   where id in (select product_id from _req) for update;
  perform 1 from product_variants
   where id in (select variant_id from _req where variant_id is not null)
     for update;

  create temp table _lines on commit drop as
  select
    p.id                                       as product_id,
    r.variant_id                               as requested_variant,
    v.id                                       as variant_id,
    p.title                                    as title,
    v.label                                    as variant_label,
    coalesce(v.price, p.price)                 as price,
    coalesce(p.price_currency, 'USD')          as currency,
    r.qty                                      as qty,
    case when r.variant_id is not null then v.stock
         else p.stock_quantity end             as stock,
    (r.variant_id is null and exists (
       select 1 from product_variants x
        where x.product_id = p.id and x.is_active)) as needs_option,
    -- image_urls is text[]. The old line called jsonb_array_length on it,
    -- which errors — so EVERY checkout failed (0 orders ever placed).
    p.image_urls[1]                            as image_url
  from _req r
  join products p on p.id = r.product_id
  left join product_variants v
         on v.id = r.variant_id and v.product_id = p.id and v.is_active
  where p.seller_id = p_seller_id
    and p.status = 'available';

  select count(*) into v_valid from _lines;
  select count(*) into v_requested from _req;
  if v_valid <> v_requested then
    raise exception 'some items are no longer available';
  end if;

  select title into v_bad from _lines
   where requested_variant is not null and variant_id is null limit 1;
  if found then
    raise exception 'OPTION_GONE: an option you chose for % is no longer available', v_bad.title;
  end if;

  select title into v_bad from _lines where needs_option limit 1;
  if found then
    raise exception 'CHOOSE_OPTION: choose a size or option for %', v_bad.title;
  end if;

  select title, variant_label, stock into v_bad from _lines
   where stock is not null and qty > stock limit 1;
  if found then
    if v_bad.stock = 0 then
      raise exception 'OUT_OF_STOCK: % is sold out',
        v_bad.title || coalesce(' (' || v_bad.variant_label || ')', '');
    else
      raise exception 'OUT_OF_STOCK: only % left of %', v_bad.stock,
        v_bad.title || coalesce(' (' || v_bad.variant_label || ')', '');
    end if;
  end if;

  select count(distinct currency) into v_valid from _lines;
  if v_valid > 1 then
    raise exception 'items must share one currency';
  end if;

  select max(currency), sum(price * qty)::numeric(12,2), sum(qty)
    into v_currency, v_subtotal, v_item_count
    from _lines;

  insert into orders (
    buyer_id, seller_id, status, currency, subtotal,
    item_count, note, buyer_name, buyer_phone
  ) values (
    v_buyer, p_seller_id, 'pending', v_currency, v_subtotal,
    v_item_count, nullif(btrim(coalesce(p_note, '')), ''),
    nullif(btrim(coalesce(p_buyer_name, '')), ''),
    nullif(btrim(coalesce(p_buyer_phone, '')), '')
  )
  returning id into v_order_id;

  insert into order_items (
    order_id, product_id, title_snapshot, price_snapshot,
    currency, qty, image_url_snapshot, variant_id, variant_label
  )
  select v_order_id, product_id, title, price, currency, qty, image_url,
         variant_id, variant_label
    from _lines;

  -- Deduct counted stock (variant rows re-total their product by trigger).
  update product_variants v
     set stock = v.stock - l.qty
    from _lines l
   where v.id = l.variant_id and v.stock is not null;
  update products p
     set stock_quantity = p.stock_quantity - l.qty
    from _lines l
   where p.id = l.product_id and l.variant_id is null
     and p.stock_quantity is not null;

  return v_order_id;
end;
$function$;

-- Cancelling puts the stock back.
CREATE OR REPLACE FUNCTION public.orders_restore_stock()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.status = 'cancelled' AND OLD.status IS DISTINCT FROM 'cancelled' THEN
    UPDATE product_variants v
       SET stock = LEAST(v.stock + oi.qty, 100000)
      FROM order_items oi
     WHERE oi.order_id = NEW.id AND oi.variant_id = v.id AND v.stock IS NOT NULL;
    UPDATE products p
       SET stock_quantity = LEAST(p.stock_quantity + oi.qty, 100000)
      FROM order_items oi
     WHERE oi.order_id = NEW.id AND oi.variant_id IS NULL
       AND oi.product_id = p.id AND p.stock_quantity IS NOT NULL;
  END IF;
  RETURN NULL;
END;
$function$;
DROP TRIGGER IF EXISTS orders_restore_stock_trg ON public.orders;
CREATE TRIGGER orders_restore_stock_trg AFTER UPDATE OF status ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.orders_restore_stock();

-- 5. Orders only through checkout ---------------------------------------------
DROP POLICY IF EXISTS orders_insert_buyer ON public.orders;
DROP POLICY IF EXISTS order_items_insert_buyer ON public.order_items;
REVOKE INSERT, DELETE, TRUNCATE ON public.orders FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.order_items FROM anon, authenticated;

COMMIT;

-- Checks:
--   * Seller sets stock 2, buyer orders 3 → "OUT_OF_STOCK: only 2 left of …".
--   * Buyer orders 2 → stock 0, card shows Sold out; cancel → stock 2 again.
--   * A product with sizes ordered without one → "CHOOSE_OPTION: …".
--   * PostgREST POST /orders as a member → permission denied.
