/// Limited progress-preservation policy for the known B2 v1 transition.
/// This is not proof that every historical content snapshot was equivalent.
const Map<String, String> journeyStationAliases = <String, String>{
  'B2-w0-4e9395bf7fb2': 'B2-w0-34914142868b',
  'B2-w1-4e9395bf7fb2': 'B2-w1-34914142868b',
  'B2-w2-4e9395bf7fb2': 'B2-w2-34914142868b',
  'B2-w3-4e9395bf7fb2': 'B2-w3-34914142868b',
  'B2-w4-4e9395bf7fb2': 'B2-w4-34914142868b',
  'B2-w5-4e9395bf7fb2': 'B2-w5-34914142868b',
  'B2-w6-4e9395bf7fb2': 'B2-w6-34914142868b',
  'B2-w7-4e9395bf7fb2': 'B2-w7-34914142868b',
  'B2-v0-4e9395bf7fb2': 'B2-v0-34914142868b',
  'B2-i0-4e9395bf7fb2': 'B2-i0-34914142868b',
  'B2-boss-4e9395bf7fb2': 'B2-boss-34914142868b',
};

String canonicalJourneyStationId(String id) => journeyStationAliases[id] ?? id;
