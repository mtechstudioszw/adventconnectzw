// Bulk music upload used the raw file name as the title — the Music shelf
// read "Love_at_Home_-_SDA_Hymn_#_652(0)". These are the real names from
// the live catalogue.

import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/utils/upload_title.dart';

void main() {
  test('real uploaded names come out readable', () {
    expect(
      titleFromFileName('Love_at_Home_-_SDA_Hymn_#_652(0).mp3'),
      'Love at Home - SDA Hymn #652',
    );
    expect(
      titleFromFileName(
        'Live_Out_Thy_Life_Within_Me_-_SDA_Hymn_#_316(0)(1).mp3',
      ),
      'Live Out Thy Life Within Me - SDA Hymn #316',
    );
    expect(
      titleFromFileName(
        'Joy_By_and_By____SDA_HYMN_#430____Breath_of_Praise(256k).mp3',
      ),
      'Joy By and By SDA HYMN #430 Breath of Praise',
    );
    expect(
      titleFromFileName('Holy,_Holy,_Holy_-_SDA_Hymn_#_73(0).mp3'),
      'Holy, Holy, Holy - SDA Hymn #73',
    );
  });

  test('an already clean name is left alone', () {
    expect(titleFromFileName('Amazing Grace.mp3'), 'Amazing Grace');
    expect(titleFromFileName('Psalm 23 (Live).mp3'), 'Psalm 23 (Live)');
  });
}
