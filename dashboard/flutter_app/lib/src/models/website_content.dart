class WebsiteMeta {
  final String title;
  final String description;

  WebsiteMeta({required this.title, required this.description});

  factory WebsiteMeta.fromJson(Map<String, dynamic> json) => WebsiteMeta(
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'description': description,
      };
}

class WebsiteHero {
  final String badge;
  final String title;
  final String subtitle;
  final String ctaPrimaryLabel;
  final String ctaPrimaryUrl;
  final String ctaSecondaryLabel;
  final String ctaSecondaryUrl;

  WebsiteHero({
    required this.badge,
    required this.title,
    required this.subtitle,
    required this.ctaPrimaryLabel,
    required this.ctaPrimaryUrl,
    required this.ctaSecondaryLabel,
    required this.ctaSecondaryUrl,
  });

  factory WebsiteHero.fromJson(Map<String, dynamic> json) => WebsiteHero(
        badge: json['badge'] as String? ?? '',
        title: json['title'] as String? ?? '',
        subtitle: json['subtitle'] as String? ?? '',
        ctaPrimaryLabel: json['cta_primary_label'] as String? ?? '',
        ctaPrimaryUrl: json['cta_primary_url'] as String? ?? '',
        ctaSecondaryLabel: json['cta_secondary_label'] as String? ?? '',
        ctaSecondaryUrl: json['cta_secondary_url'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'badge': badge,
        'title': title,
        'subtitle': subtitle,
        'cta_primary_label': ctaPrimaryLabel,
        'cta_primary_url': ctaPrimaryUrl,
        'cta_secondary_label': ctaSecondaryLabel,
        'cta_secondary_url': ctaSecondaryUrl,
      };

  WebsiteHero copyWith({
    String? badge,
    String? title,
    String? subtitle,
    String? ctaPrimaryLabel,
    String? ctaPrimaryUrl,
    String? ctaSecondaryLabel,
    String? ctaSecondaryUrl,
  }) =>
      WebsiteHero(
        badge: badge ?? this.badge,
        title: title ?? this.title,
        subtitle: subtitle ?? this.subtitle,
        ctaPrimaryLabel: ctaPrimaryLabel ?? this.ctaPrimaryLabel,
        ctaPrimaryUrl: ctaPrimaryUrl ?? this.ctaPrimaryUrl,
        ctaSecondaryLabel: ctaSecondaryLabel ?? this.ctaSecondaryLabel,
        ctaSecondaryUrl: ctaSecondaryUrl ?? this.ctaSecondaryUrl,
      );
}

class AppEntry {
  final String id;
  final String name;
  final String icon;
  final String tag;
  final String tagStyle;
  final String description;
  final List<String> platforms;
  final String? appStoreUrl;
  final String? playStoreUrl;
  final bool featured;
  final bool comingSoon;

  AppEntry({
    required this.id,
    required this.name,
    required this.icon,
    required this.tag,
    required this.tagStyle,
    required this.description,
    required this.platforms,
    this.appStoreUrl,
    this.playStoreUrl,
    this.featured = false,
    this.comingSoon = false,
  });

  factory AppEntry.fromJson(Map<String, dynamic> json) => AppEntry(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        icon: json['icon'] as String? ?? '',
        tag: json['tag'] as String? ?? '',
        tagStyle: json['tag_style'] as String? ?? 'default',
        description: json['description'] as String? ?? '',
        platforms: (json['platforms'] as List? ?? []).cast<String>(),
        appStoreUrl: json['app_store_url'] as String?,
        playStoreUrl: json['play_store_url'] as String?,
        featured: json['featured'] as bool? ?? false,
        comingSoon: json['coming_soon'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'icon': icon,
        'tag': tag,
        'tag_style': tagStyle,
        'description': description,
        'platforms': platforms,
        'app_store_url': appStoreUrl,
        'play_store_url': playStoreUrl,
        'featured': featured,
        'coming_soon': comingSoon,
      };

  AppEntry copyWith({
    String? description,
    String? appStoreUrl,
    String? playStoreUrl,
    bool? comingSoon,
  }) =>
      AppEntry(
        id: id,
        name: name,
        icon: icon,
        tag: tag,
        tagStyle: tagStyle,
        description: description ?? this.description,
        platforms: platforms,
        appStoreUrl: appStoreUrl ?? this.appStoreUrl,
        playStoreUrl: playStoreUrl ?? this.playStoreUrl,
        featured: featured,
        comingSoon: comingSoon ?? this.comingSoon,
      );
}

class WebsiteContent {
  final WebsiteMeta meta;
  final WebsiteHero hero;
  final String signupUrl;
  final String loginUrl;
  final List<AppEntry> apps;

  WebsiteContent({
    required this.meta,
    required this.hero,
    required this.signupUrl,
    required this.loginUrl,
    required this.apps,
  });

  factory WebsiteContent.fromJson(Map<String, dynamic> json) => WebsiteContent(
        meta: WebsiteMeta.fromJson(json['meta'] as Map<String, dynamic>? ?? {}),
        hero: WebsiteHero.fromJson(json['hero'] as Map<String, dynamic>? ?? {}),
        signupUrl: json['signup_url'] as String? ?? '',
        loginUrl: json['login_url'] as String? ?? '',
        apps: (json['apps'] as List? ?? [])
            .map((a) => AppEntry.fromJson(a as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'meta': meta.toJson(),
        'hero': hero.toJson(),
        'signup_url': signupUrl,
        'login_url': loginUrl,
        'apps': apps.map((a) => a.toJson()).toList(),
      };
}

class WebsiteDeployRun {
  final int id;
  final String status;
  final String? conclusion;
  final String createdAt;
  final String? duration;
  final String url;

  WebsiteDeployRun({
    required this.id,
    required this.status,
    this.conclusion,
    required this.createdAt,
    this.duration,
    required this.url,
  });

  factory WebsiteDeployRun.fromJson(Map<String, dynamic> json) =>
      WebsiteDeployRun(
        id: json['id'] as int? ?? 0,
        status: json['status'] as String? ?? '',
        conclusion: json['conclusion'] as String?,
        createdAt: json['created_at'] as String? ?? '',
        duration: json['duration'] as String?,
        url: json['url'] as String? ?? '',
      );
}
