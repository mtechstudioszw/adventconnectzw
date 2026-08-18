-- =====================================================================
--  PATCH 211 — end-to-end encryption: the key directory
--
--  The server side of E2EE, and deliberately ONLY that. Nothing here can
--  read a message. What it stores is the public half of each device's
--  keys, so one member can start an encrypted session with another who
--  is offline — the X3DH property that makes "message someone who isn't
--  running the app" possible at all.
--
--  Private keys NEVER leave the device. There is no column for one here,
--  and there must never be: the moment the server can hold a private
--  key, "end-to-end" is a marketing claim rather than a property, and
--  the notice the app is about to print in every chat becomes a lie.
--
--  SHAPE (Signal protocol, the one WhatsApp runs)
--
--   e2ee_devices        one row per (user, device). Identity public key
--                       plus the registration id. A reinstall is a NEW
--                       device row, which is what makes the peer's
--                       "security code changed" notice possible.
--
--   e2ee_signed_prekeys the medium-term key, signed by the identity key
--                       so a recipient can prove it came from that
--                       device. Rotated periodically; old ones are kept
--                       briefly so in-flight messages still open.
--
--   e2ee_prekeys        one-time prekeys. CONSUMED on use — this is the
--                       part that needs a transaction, see
--                       claim_prekey_bundle() below.
--
--  WHAT IS NOT HERE
--
--   * Group sender keys. They are distributed to members THROUGH the
--     pairwise encrypted channel, so the server never sees one. Putting
--     them in a table would hand the server the group's message key and
--     undo the whole exercise.
--   * Any key backup. Founder chose WhatsApp's default: a reinstall
--     loses history. There is nothing to restore from, on purpose.
--
--  IDEMPOTENT: yes.
-- =====================================================================


-- ----- 1. Devices ----------------------------------------------------
CREATE TABLE IF NOT EXISTS public.e2ee_devices (
  user_id         uuid    NOT NULL REFERENCES public.profiles(id)
                            ON DELETE CASCADE,
  device_id       int     NOT NULL,
  registration_id int     NOT NULL,
  -- Base64 of the serialised IdentityKey. PUBLIC half only.
  identity_key    text    NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT NOW(),
  last_seen_at    timestamptz NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, device_id)
);

-- ----- 2. Signed prekeys ---------------------------------------------
CREATE TABLE IF NOT EXISTS public.e2ee_signed_prekeys (
  user_id     uuid NOT NULL,
  device_id   int  NOT NULL,
  key_id      int  NOT NULL,
  public_key  text NOT NULL,
  signature   text NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, device_id, key_id),
  FOREIGN KEY (user_id, device_id)
    REFERENCES public.e2ee_devices(user_id, device_id) ON DELETE CASCADE
);

-- ----- 3. One-time prekeys -------------------------------------------
-- `claimed_at` rather than a DELETE so a double-claim is visible in the
-- data instead of silently handing two senders the same prekey.
CREATE TABLE IF NOT EXISTS public.e2ee_prekeys (
  user_id     uuid NOT NULL,
  device_id   int  NOT NULL,
  key_id      int  NOT NULL,
  public_key  text NOT NULL,
  claimed_at  timestamptz,
  created_at  timestamptz NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, device_id, key_id),
  FOREIGN KEY (user_id, device_id)
    REFERENCES public.e2ee_devices(user_id, device_id) ON DELETE CASCADE
);

-- The claim query: cheapest unclaimed prekey for a device.
CREATE INDEX IF NOT EXISTS idx_e2ee_prekeys_unclaimed
  ON public.e2ee_prekeys (user_id, device_id)
  WHERE claimed_at IS NULL;


-- ----- 4. RLS --------------------------------------------------------
ALTER TABLE public.e2ee_devices        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.e2ee_signed_prekeys ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.e2ee_prekeys        ENABLE ROW LEVEL SECURITY;

-- Writes: your own device rows, and nobody else's. A member who could
-- write someone else's identity key could substitute their own and read
-- that person's mail — this is THE policy that matters on these tables.
DROP POLICY IF EXISTS e2ee_devices_write_self ON public.e2ee_devices;
CREATE POLICY e2ee_devices_write_self ON public.e2ee_devices
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS e2ee_signed_prekeys_write_self
  ON public.e2ee_signed_prekeys;
CREATE POLICY e2ee_signed_prekeys_write_self ON public.e2ee_signed_prekeys
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS e2ee_prekeys_write_self ON public.e2ee_prekeys;
CREATE POLICY e2ee_prekeys_write_self ON public.e2ee_prekeys
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- Reads go through claim_prekey_bundle() only. No SELECT policy for
-- other people's rows is created on purpose: a directory that can be
-- enumerated tells an attacker exactly which members are reachable and
-- how many prekeys each has left.


-- ----- 5. Claiming a bundle ------------------------------------------
-- Atomically takes ONE unclaimed prekey and returns the bundle needed to
-- open a session. SECURITY DEFINER because the caller has no SELECT on
-- another member's key rows, by design.
--
-- The UPDATE ... RETURNING is the whole point: two senders starting a
-- chat with the same person at the same moment must not receive the same
-- one-time prekey. `FOR UPDATE SKIP LOCKED` lets the second one take the
-- next prekey instead of blocking on the first.
--
-- Running OUT of prekeys is not an error. The bundle comes back with a
-- null prekey and X3DH falls back to the signed prekey alone — weaker
-- forward secrecy for that first message, still encrypted, and the
-- client tops its prekeys back up on next launch.
CREATE OR REPLACE FUNCTION public.claim_prekey_bundle(p_user uuid)
RETURNS TABLE (
  device_id       int,
  registration_id int,
  identity_key    text,
  signed_key_id   int,
  signed_key      text,
  signed_sig      text,
  prekey_id       int,
  prekey          text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_device   int;
  v_prekey   RECORD;
BEGIN
  -- Blocks cut both ways here as everywhere else: you cannot open an
  -- encrypted session with someone who has blocked you, or whom you have
  -- blocked, because you cannot message them either.
  IF public.is_blocked_by(p_user) THEN
    RETURN;
  END IF;

  SELECT d.device_id INTO v_device
    FROM public.e2ee_devices d
   WHERE d.user_id = p_user
   ORDER BY d.last_seen_at DESC
   LIMIT 1;

  IF v_device IS NULL THEN
    RETURN; -- not on an E2EE build yet
  END IF;

  -- Take one unclaimed prekey, if any are left.
  UPDATE public.e2ee_prekeys k
     SET claimed_at = NOW()
   WHERE (k.user_id, k.device_id, k.key_id) = (
     SELECT s.user_id, s.device_id, s.key_id
       FROM public.e2ee_prekeys s
      WHERE s.user_id = p_user
        AND s.device_id = v_device
        AND s.claimed_at IS NULL
      ORDER BY s.key_id
      FOR UPDATE SKIP LOCKED
      LIMIT 1
   )
  RETURNING k.key_id, k.public_key INTO v_prekey;

  RETURN QUERY
  SELECT
    d.device_id,
    d.registration_id,
    d.identity_key,
    sp.key_id,
    sp.public_key,
    sp.signature,
    v_prekey.key_id,
    v_prekey.public_key
  FROM public.e2ee_devices d
  JOIN public.e2ee_signed_prekeys sp
    ON sp.user_id = d.user_id AND sp.device_id = d.device_id
  WHERE d.user_id = p_user
    AND d.device_id = v_device
  ORDER BY sp.created_at DESC
  LIMIT 1;
END;
$function$;

REVOKE ALL ON FUNCTION public.claim_prekey_bundle(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.claim_prekey_bundle(uuid) TO authenticated;


-- ----- 6. How many prekeys are left ----------------------------------
-- The client tops up when this runs low. Own device only.
CREATE OR REPLACE FUNCTION public.my_unclaimed_prekey_count(p_device int)
RETURNS int
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT COUNT(*)::int
    FROM public.e2ee_prekeys
   WHERE user_id = auth.uid()
     AND device_id = p_device
     AND claimed_at IS NULL;
$function$;

REVOKE ALL ON FUNCTION public.my_unclaimed_prekey_count(int)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.my_unclaimed_prekey_count(int)
  TO authenticated;


-- ----- 7. The message envelope ---------------------------------------
-- Encrypted messages keep using `messages`. `content` holds the base64
-- ciphertext and `e2ee_version` marks it as such, so a client that has
-- not been updated yet shows the placeholder rather than a wall of
-- base64.
--
-- `ciphertext_type` distinguishes a PreKeySignalMessage (opens a
-- session) from an ordinary SignalMessage — the recipient MUST know
-- which before it can decrypt, and it is not derivable from the bytes
-- without guessing.
--
-- NOT NULL is deliberately absent: every existing row predates this and
-- stays readable. E2EE applies to messages sent from here on. There is
-- no way to retro-encrypt history, and pretending otherwise would mean
-- the server reading every message to do it.
ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS e2ee_version    smallint,
  ADD COLUMN IF NOT EXISTS sender_device_id int,
  ADD COLUMN IF NOT EXISTS ciphertext_type  smallint;
