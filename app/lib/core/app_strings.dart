/// All reader-facing strings, in the three publication languages.
///
/// Adding a fourth language means adding a column here and nothing else; the
/// rest of the app looks strings up through [AppStrings.of].
///
/// `te`  — Telugu script, the primary language of the paper.
/// `ten` — Tenglish (Telugu in the Roman alphabet), the second script.
/// `en`  – English.
library;

import 'package:flutter/widgets.dart';

import 'config.dart';

class AppStrings {
  const AppStrings(this.code);

  final String code;

  static AppStrings of(BuildContext context, String code) {
    return AppStrings(code);
  }

  static const Map<String, _Lang> _table = {
    'te': _Lang(
      appName: 'దశ న్యూస్',
      tagline: 'తెలంగాణకు మొదటి',
      home: 'హోమ్',
      explore: 'విభాగాలు',
      breaking: 'బ్రేకింగ్',
      shorts: 'షార్ట్స్',
      audio: 'ఆడియో',
      search: 'వెతకండి',
      saved: 'సేవ్ చేసినవి',
      profile: 'ప్రొఫైల్',
      settings: 'అమరికలు',
      language: 'భాష',
      theme: 'థీమ్',
      light: 'లైట్',
      dark: 'డార్క్',
      system: 'సిస్టమ్',
      district: 'జిల్లా',
      allDistricts: 'అన్ని జిల్లాలు',
      stateEdition: 'రాష్ట్రం',
      latest: 'తాజా',
      developing: 'కొనసాగుతున్న',
      reading: 'చదువుతున్నారు',
      readAtSource: 'మూలంలో చదవండి',
      saveStory: 'సేవ్ చేయండి',
      savedStory: 'సేవ్ అయింది',
      shareStory: 'షేర్ చేయండి',
      sources: 'మూలాలు',
      facts: 'వాస్తవాలు',
      evidence: 'ఆధారం',
      confidence: 'నమ్మకం',
      attributedTo: 'చెప్పినది',
      corroborated: 'ధృవీకరించబడింది',
      inConflict: 'మూలాల మధ్య భేదం',
      corrections: 'సవరణలు',
      updates: 'నవీకరణలు',
      listen: 'వినండి',
      pause: 'ఆపండి',
      resume: 'కొనసాగించండి',
      minRead: 'నిమిషాలు',
      justNow: 'ఇప్పుడే',
      minutesAgo: 'నిమిషాల క్రితం',
      hoursAgo: 'గంటల క్రితం',
      daysAgo: 'రోజుల క్రితం',
      onboardingTitle: 'దశ న్యూస్‌కి స్వాగతం',
      onboardingBody:
          'తెలంగాణ కోసం నిర్మించిన వార్తా పత్రిక. మీ భాష, మీ జిల్లా, మీ ఇష్టం ప్రకారం వార్తలు.',
      chooseLanguage: 'మీ భాషను ఎంచుకోండి',
      chooseDistrict: 'మీ జిల్లాను ఎంచుకోండి',
      getStarted: 'ప్రారంభించండి',
      next: 'తరువాత',
      skip: 'దాటవేయి',
      feedEmpty: 'ఇంకా వార్తలు లేవు',
      feedEmptyHint: 'కొద్దిసేపట్లో మళ్లీ ప్రయత్నించండి',
      searchEmpty: 'ఫలితాలు లేవు',
      searchHint: 'వార్తల కోసం వెతకండి',
      bookmarksEmpty: 'సేవ్ చేసిన వార్తలు లేవు',
      bookmarksEmptyHint: 'చదువుతున్నప్పుడు సేవ్ చేయండి',
      offline: 'ఆఫ్‌లైన్',
      online: 'ఆన్‌లైన్',
      offlineHint: 'చివరిగా దాచిన వార్తలు చూపిస్తున్నాము',
      errorGeneric: 'ఏదో తప్పు జరిగింది',
      errorOffline: 'వార్తలను చేరుకోలేకపోయాము',
      ok: 'సరే',
      cancel: 'రద్దు చేయి',
      notFound: 'పేజీ దొరకలేదు',
      retry: 'మళ్లీ ప్రయత్నించండి',
      loadMore: 'మరిన్ని లోడ్ చేయండి',
      loading: 'లోడ్ అవుతోంది',
      submitTip: 'వార్త పంపండి',
      tipBody: 'మీకు తెలిసిన వార్తను రాయండి',
      tipBodyHint: 'కనీసం పది అక్షరాలు…',
      tipLocation: 'ప్రాంతం (ఐచ్ఛికం)',
      tipContact: 'మీ పేరు లేదా ఫోన్ (ఐచ్ఛికం)',
      tipSubmitted: 'ధన్యవాదాలు! మీ వార్త సమీక్షలో ఉంది',
      tipTooShort: 'దయచేసి మరింత వివరంగా రాయండి',
      breakingAlerts: 'బ్రేకింగ్ అలర్ట్‌లు',
      dailyDigest: 'రోజువారీ సారాంశం',
      clearCache: 'క్యాష్ క్లియర్ చేయండి',
      cacheCleared: 'క్యాష్ క్లియర్ అయింది',
      resetIdentity: 'డివైస్ ఐడీని రీసెట్ చేయండి',
      identityReset: 'మీ గుర్తింపు రీసెట్ అయింది',
      server: 'సర్వర్',
      serverHint: 'న్యూస్‌రూమ్ చిరునామా',
      about: 'గురించి',
      aboutBody:
          'దశ న్యూస్ అనేది తెలంగాణకు చెందిన AI ఆధారిత డిజిటల్ వార్తా పత్రిక. ప్రతి వార్తకు మూలం, ఆధారం స్థాయి, '
          'మరియు ఎంతమంది మూలాలు నివేదించాయో బహిరంగంగా చూపిస్తుంది.',
      originalVsSummary: 'ఇది అసలు నివేదన కాదు; దశ సారాంశం.',
      unpublished: 'ప్రచురణకు ముందే',
      holdNote: 'సంపాదకీయ పర్యవేక్షణలో ఉంది',
    ),
    'ten': _Lang(
      appName: 'Dasha News',
      tagline: 'Telangana ki modati',
      home: 'Home',
      explore: 'Vibhagalu',
      breaking: 'Breaking',
      shorts: 'Shorts',
      audio: 'Audio',
      search: 'Vethakandi',
      saved: 'Save chesinavi',
      profile: 'Profile',
      settings: 'Amarikalu',
      language: 'Basha',
      theme: 'Theme',
      light: 'Light',
      dark: 'Dark',
      system: 'System',
      district: 'Jilla',
      allDistricts: 'Anni jillalu',
      stateEdition: 'Rajyam',
      latest: 'Taja',
      developing: 'Konasagutunna',
      reading: 'Chaduvutunnaru',
      readAtSource: 'Moolamlo chadavandi',
      saveStory: 'Save cheyandi',
      savedStory: 'Save aindi',
      shareStory: 'Share cheyandi',
      sources: 'Moolalu',
      facts: 'Vastavalu',
      evidence: 'Aadhaaram',
      confidence: 'Nammakam',
      attributedTo: 'Cheppindi',
      corroborated: 'Dhruveekarinchabaddindi',
      inConflict: 'Moolala madhya bhedam',
      corrections: 'Savaralu',
      updates: 'Navikaranalu',
      listen: 'Vinandi',
      pause: 'Aapandi',
      resume: 'Konasaginchandi',
      minRead: 'nimishalu',
      justNow: 'Ippude',
      minutesAgo: 'nimishala kritam',
      hoursAgo: 'gantala kritam',
      daysAgo: 'rojula kritam',
      onboardingTitle: 'Dasha News ki swagatam',
      onboardingBody:
          'Telangana kosam nirminchina vaartha patrika. Mi basha, mi jilla, mi ishtam prakaram vaarthalu.',
      chooseLanguage: 'Mi bashanu enchukondi',
      chooseDistrict: 'Mi jillanu enchukondi',
      getStarted: 'Prarambhinchandi',
      next: 'Taruvatha',
      skip: 'Dataveyi',
      feedEmpty: 'Inkaa vaarthalu levu',
      feedEmptyHint: 'Koddiseepulo malli prayatninchandi',
      searchEmpty: 'Falithalu levu',
      searchHint: 'Vaarthala kosam vethakandi',
      bookmarksEmpty: 'Save chesina vaarthalu levu',
      bookmarksEmptyHint: 'Chaduvutunappudu save cheyandi',
      offline: 'Offline',
      online: 'Online',
      offlineHint: 'Chivarigi dachina vaarthalu chupistunnamu',
      errorGeneric: 'Edo tappu jarigindi',
      errorOffline: 'Vaarthalanu cherukole poyamu',
      ok: 'Sare',
      cancel: 'Raddu cheyyi',
      notFound: 'Page dorakaledu',
      retry: 'Malli prayatninchandi',
      loadMore: 'Marinni load cheyandi',
      loading: 'Load avutondi',
      submitTip: 'Vaartha pampandi',
      tipBody: 'Miku telisina vaarthani rayandi',
      tipBodyHint: 'Kaneesam padi aksharalu…',
      tipLocation: 'Prantam (aichchikam)',
      tipContact: 'Mi peru leda phone (aichchikam)',
      tipSubmitted: 'Dhanyavaadalu! Mi vaartha sameekshalo undi',
      tipTooShort: 'Dayachesi marinta vivaranga rayandi',
      breakingAlerts: 'Breaking alerts',
      dailyDigest: 'Rojuvaari saaraamsham',
      clearCache: 'Cache clear cheyandi',
      cacheCleared: 'Cache clear aindi',
      resetIdentity: 'Device ID ni reset cheyandi',
      identityReset: 'Mi gurtimpu reset aindi',
      server: 'Server',
      serverHint: 'Newsroom chirunama',
      about: 'Gurinchi',
      aboutBody:
          'Dasha News anedhi Telanganaki chendina AI aadharitha digital vaartha patrika. Prati vaarthaku '
          'moolam, aadhaaram sthayi, mariu enthamandri moolalu nivedinchayo bahiranganga chupistundi.',
      originalVsSummary: 'Idi asalu nivedana kaadu; Dasha saaraamsham.',
      unpublished: 'Prachuranaku mundhe',
      holdNote: 'Sampadakeeya paryavekshanalo undi',
    ),
    'en': _Lang(
      appName: 'Dasha News',
      tagline: 'Telangana first',
      home: 'Home',
      explore: 'Sections',
      breaking: 'Breaking',
      shorts: 'Shorts',
      audio: 'Audio',
      search: 'Search',
      saved: 'Saved',
      profile: 'Profile',
      settings: 'Settings',
      language: 'Language',
      theme: 'Theme',
      light: 'Light',
      dark: 'Dark',
      system: 'System',
      district: 'District',
      allDistricts: 'All districts',
      stateEdition: 'State',
      latest: 'Latest',
      developing: 'Developing',
      reading: 'reading',
      readAtSource: 'Read at source',
      saveStory: 'Save',
      savedStory: 'Saved',
      shareStory: 'Share',
      sources: 'Sources',
      facts: 'Facts',
      evidence: 'Evidence',
      confidence: 'Confidence',
      attributedTo: 'According to',
      corroborated: 'Corroborated',
      inConflict: 'Sources conflict',
      corrections: 'Corrections',
      updates: 'Updates',
      listen: 'Listen',
      pause: 'Pause',
      resume: 'Resume',
      minRead: 'min read',
      justNow: 'just now',
      minutesAgo: 'min ago',
      hoursAgo: 'h ago',
      daysAgo: 'd ago',
      onboardingTitle: 'Welcome to Dasha News',
      onboardingBody:
          'A digital newspaper built for Telangana. News in your language, from your district, '
          'with its sources in the open.',
      chooseLanguage: 'Choose your language',
      chooseDistrict: 'Choose your district',
      getStarted: 'Get started',
      next: 'Next',
      skip: 'Skip',
      feedEmpty: 'No stories yet',
      feedEmptyHint: 'Please try again in a moment',
      searchEmpty: 'No results',
      searchHint: 'Search the news',
      bookmarksEmpty: 'Nothing saved yet',
      bookmarksEmptyHint: 'Save a story while you read it',
      offline: 'Offline',
      online: 'Online',
      offlineHint: 'Showing the last stories we could keep',
      errorGeneric: 'Something went wrong',
      errorOffline: 'Could not reach the newsroom',
      ok: 'OK',
      cancel: 'Cancel',
      notFound: 'Page not found',
      retry: 'Try again',
      loadMore: 'Load more',
      loading: 'Loading',
      submitTip: 'Send a tip',
      tipBody: 'Tell us what you know',
      tipBodyHint: 'At least ten characters…',
      tipLocation: 'Location (optional)',
      tipContact: 'Your name or phone (optional)',
      tipSubmitted: 'Thank you! Your tip is with our editors',
      tipTooShort: 'Please tell us a little more',
      breakingAlerts: 'Breaking alerts',
      dailyDigest: 'Daily digest',
      clearCache: 'Clear cache',
      cacheCleared: 'Cache cleared',
      resetIdentity: 'Reset device identity',
      identityReset: 'Your identity has been reset',
      server: 'Server',
      serverHint: 'Newsroom address',
      about: 'About',
      aboutBody:
          'Dasha News is an AI-assisted digital newspaper for Telangana. Every story shows its '
          'sources, the evidence level of each claim, and how many outlets reported it.',
      originalVsSummary: 'This is a Dasha summary, not the original report.',
      unpublished: 'Not yet published',
      holdNote: 'Held for editorial review',
    ),
  };

  _Lang get _lang => _table[code] ?? _table['en']!;

  // Convenience accessors keep call sites readable.
  String get appName => _lang.appName;
  String get tagline => _lang.tagline;
  String get home => _lang.home;
  String get explore => _lang.explore;
  String get breaking => _lang.breaking;
  String get shorts => _lang.shorts;
  String get audio => _lang.audio;
  String get search => _lang.search;
  String get saved => _lang.saved;
  String get profile => _lang.profile;
  String get settings => _lang.settings;
  String get language => _lang.language;
  String get theme => _lang.theme;
  String get light => _lang.light;
  String get dark => _lang.dark;
  String get system => _lang.system;
  String get district => _lang.district;
  String get allDistricts => _lang.allDistricts;
  String get stateEdition => _lang.stateEdition;
  String get latest => _lang.latest;
  String get developing => _lang.developing;
  String get reading => _lang.reading;
  String get readAtSource => _lang.readAtSource;
  String get saveStory => _lang.saveStory;
  String get savedStory => _lang.savedStory;
  String get shareStory => _lang.shareStory;
  String get sources => _lang.sources;
  String get facts => _lang.facts;
  String get evidence => _lang.evidence;
  String get confidence => _lang.confidence;
  String get attributedTo => _lang.attributedTo;
  String get corroborated => _lang.corroborated;
  String get inConflict => _lang.inConflict;
  String get corrections => _lang.corrections;
  String get updates => _lang.updates;
  String get listen => _lang.listen;
  String get pause => _lang.pause;
  String get resume => _lang.resume;
  String get minRead => _lang.minRead;
  String get justNow => _lang.justNow;
  String get minutesAgo => _lang.minutesAgo;
  String get hoursAgo => _lang.hoursAgo;
  String get daysAgo => _lang.daysAgo;
  String get onboardingTitle => _lang.onboardingTitle;
  String get onboardingBody => _lang.onboardingBody;
  String get chooseLanguage => _lang.chooseLanguage;
  String get chooseDistrict => _lang.chooseDistrict;
  String get getStarted => _lang.getStarted;
  String get next => _lang.next;
  String get skip => _lang.skip;
  String get feedEmpty => _lang.feedEmpty;
  String get feedEmptyHint => _lang.feedEmptyHint;
  String get searchEmpty => _lang.searchEmpty;
  String get searchHint => _lang.searchHint;
  String get bookmarksEmpty => _lang.bookmarksEmpty;
  String get bookmarksEmptyHint => _lang.bookmarksEmptyHint;
  String get offline => _lang.offline;
  String get online => _lang.online;
  String get offlineHint => _lang.offlineHint;
  String get errorGeneric => _lang.errorGeneric;
  String get errorOffline => _lang.errorOffline;
  String get ok => _lang.ok;
  String get cancel => _lang.cancel;
  String get notFound => _lang.notFound;
  String get retry => _lang.retry;
  String get loadMore => _lang.loadMore;
  String get loading => _lang.loading;
  String get submitTip => _lang.submitTip;
  String get tipBody => _lang.tipBody;
  String get tipBodyHint => _lang.tipBodyHint;
  String get tipLocation => _lang.tipLocation;
  String get tipContact => _lang.tipContact;
  String get tipSubmitted => _lang.tipSubmitted;
  String get tipTooShort => _lang.tipTooShort;
  String get breakingAlerts => _lang.breakingAlerts;
  String get dailyDigest => _lang.dailyDigest;
  String get clearCache => _lang.clearCache;
  String get cacheCleared => _lang.cacheCleared;
  String get resetIdentity => _lang.resetIdentity;
  String get identityReset => _lang.identityReset;
  String get server => _lang.server;
  String get serverHint => _lang.serverHint;
  String get about => _lang.about;
  String get aboutBody => _lang.aboutBody;
  String get originalVsSummary => _lang.originalVsSummary;
  String get unpublished => _lang.unpublished;
  String get holdNote => _lang.holdNote;

  /// Human-readable name of a language code, in that language.
  static String nameOf(String code) {
    switch (code) {
      case 'te':
        return 'తెలుగు';
      case 'ten':
        return 'Tenglish';
      default:
        return 'English';
    }
  }

  /// The two script-bearing languages, for the onboarding picker.
  static List<String> get pickerChoices => supportedLocales;
}

class _Lang {
  const _Lang({
    required this.appName,
    required this.tagline,
    required this.home,
    required this.explore,
    required this.breaking,
    required this.shorts,
    required this.audio,
    required this.search,
    required this.saved,
    required this.profile,
    required this.settings,
    required this.language,
    required this.theme,
    required this.light,
    required this.dark,
    required this.system,
    required this.district,
    required this.allDistricts,
    required this.stateEdition,
    required this.latest,
    required this.developing,
    required this.reading,
    required this.readAtSource,
    required this.saveStory,
    required this.savedStory,
    required this.shareStory,
    required this.sources,
    required this.facts,
    required this.evidence,
    required this.confidence,
    required this.attributedTo,
    required this.corroborated,
    required this.inConflict,
    required this.corrections,
    required this.updates,
    required this.listen,
    required this.pause,
    required this.resume,
    required this.minRead,
    required this.justNow,
    required this.minutesAgo,
    required this.hoursAgo,
    required this.daysAgo,
    required this.onboardingTitle,
    required this.onboardingBody,
    required this.chooseLanguage,
    required this.chooseDistrict,
    required this.getStarted,
    required this.next,
    required this.skip,
    required this.feedEmpty,
    required this.feedEmptyHint,
    required this.searchEmpty,
    required this.searchHint,
    required this.bookmarksEmpty,
    required this.bookmarksEmptyHint,
    required this.offline,
    required this.online,
    required this.offlineHint,
    required this.errorGeneric,
    required this.errorOffline,
    required this.ok,
    required this.cancel,
    required this.notFound,
    required this.retry,
    required this.loadMore,
    required this.loading,
    required this.submitTip,
    required this.tipBody,
    required this.tipBodyHint,
    required this.tipLocation,
    required this.tipContact,
    required this.tipSubmitted,
    required this.tipTooShort,
    required this.breakingAlerts,
    required this.dailyDigest,
    required this.clearCache,
    required this.cacheCleared,
    required this.resetIdentity,
    required this.identityReset,
    required this.server,
    required this.serverHint,
    required this.about,
    required this.aboutBody,
    required this.originalVsSummary,
    required this.unpublished,
    required this.holdNote,
  });

  final String appName;
  final String tagline;
  final String home;
  final String explore;
  final String breaking;
  final String shorts;
  final String audio;
  final String search;
  final String saved;
  final String profile;
  final String settings;
  final String language;
  final String theme;
  final String light;
  final String dark;
  final String system;
  final String district;
  final String allDistricts;
  final String stateEdition;
  final String latest;
  final String developing;
  final String reading;
  final String readAtSource;
  final String saveStory;
  final String savedStory;
  final String shareStory;
  final String sources;
  final String facts;
  final String evidence;
  final String confidence;
  final String attributedTo;
  final String corroborated;
  final String inConflict;
  final String corrections;
  final String updates;
  final String listen;
  final String pause;
  final String resume;
  final String minRead;
  final String justNow;
  final String minutesAgo;
  final String hoursAgo;
  final String daysAgo;
  final String onboardingTitle;
  final String onboardingBody;
  final String chooseLanguage;
  final String chooseDistrict;
  final String getStarted;
  final String next;
  final String skip;
  final String feedEmpty;
  final String feedEmptyHint;
  final String searchEmpty;
  final String searchHint;
  final String bookmarksEmpty;
  final String bookmarksEmptyHint;
  final String offline;
  final String online;
  final String offlineHint;
  final String errorGeneric;
  final String errorOffline;
  final String ok;
  final String cancel;
  final String notFound;
  final String retry;
  final String loadMore;
  final String loading;
  final String submitTip;
  final String tipBody;
  final String tipBodyHint;
  final String tipLocation;
  final String tipContact;
  final String tipSubmitted;
  final String tipTooShort;
  final String breakingAlerts;
  final String dailyDigest;
  final String clearCache;
  final String cacheCleared;
  final String resetIdentity;
  final String identityReset;
  final String server;
  final String serverHint;
  final String about;
  final String aboutBody;
  final String originalVsSummary;
  final String unpublished;
  final String holdNote;
}
