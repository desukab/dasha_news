/// The shapes the newsroom returns.
///
/// Every field is nullable that the newsroom may legitimately not have: an
/// automated story has no editor's English prose yet, a manual story has no
/// source links, a draft has no published timestamp. The UI renders the gap,
/// it does not paper over it with placeholder text that reads like fact.
library;

import 'package:flutter/foundation.dart';

@immutable
class FactView {
  const FactView({
    required this.id,
    required this.textTe,
    required this.evidenceLevel,
    required this.rank,
    this.textEn,
    this.evidenceLabelTe,
    this.evidenceLabelEn,
    this.confidence = 0.0,
    this.attributedTo,
    this.status = 'active',
  });

  factory FactView.fromJson(Map<String, dynamic> json) {
    return FactView(
      id: json['id'] as int,
      textTe: json['text_te'] as String,
      textEn: json['text_en'] as String?,
      evidenceLevel: json['evidence_level'] as String,
      evidenceLabelTe: json['evidence_label_te'] as String?,
      evidenceLabelEn: json['evidence_label_en'] as String?,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      attributedTo: json['attributed_to'] as String?,
      status: json['status'] as String? ?? 'active',
      rank: json['rank'] as int? ?? 0,
    );
  }

  final int id;
  final String textTe;
  final String? textEn;
  final String evidenceLevel;
  final String? evidenceLabelTe;
  final String? evidenceLabelEn;
  final double confidence;
  final String? attributedTo;
  final String status;
  final int rank;

  /// Withdrawn facts stay in the audit trail but are not shown as live.
  bool get isActive => status == 'active';
}

@immutable
class SourceLinkView {
  const SourceLinkView({
    required this.id,
    required this.corroborates,
    this.sourceName,
    this.siteUrl,
    this.articleUrl,
    this.articleTitle,
    this.publishedAt,
    this.conflictsWith,
  });

  factory SourceLinkView.fromJson(Map<String, dynamic> json) {
    return SourceLinkView(
      id: json['id'] as int,
      sourceName: json['source_name'] as String?,
      siteUrl: json['site_url'] as String?,
      articleUrl: json['article_url'] as String?,
      articleTitle: json['article_title'] as String?,
      publishedAt: json['published_at'] as String?,
      conflictsWith: json['conflicts_with'] as String?,
      corroborates: json['corroborates'] as bool? ?? false,
    );
  }

  final int id;
  final String? sourceName;
  final String? siteUrl;
  final String? articleUrl;
  final String? articleTitle;
  final String? publishedAt;
  final String? conflictsWith;
  final bool corroborates;
}

@immutable
class UpdateView {
  const UpdateView({
    required this.id,
    required this.kind,
    required this.createdAt,
    this.headline,
    this.textTe,
    this.textEn,
    this.appliedBy,
  });

  factory UpdateView.fromJson(Map<String, dynamic> json) {
    return UpdateView(
      id: json['id'] as int,
      kind: json['kind'] as String,
      headline: json['headline'] as String?,
      textTe: json['text_te'] as String?,
      textEn: json['text_en'] as String?,
      appliedBy: json['applied_by'] as String?,
      createdAt: json['created_at'] as String,
    );
  }

  final int id;
  final String kind;
  final String? headline;
  final String? textTe;
  final String? textEn;
  final String? appliedBy;
  final String createdAt;
}

@immutable
class StoryDetail {
  const StoryDetail({
    required this.id,
    required this.clusterId,
    required this.slug,
    required this.section,
    required this.status,
    required this.origin,
    required this.editorLocked,
    required this.needsReview,
    required this.numSources,
    required this.importance,
    required this.evidenceScore,
    required this.facts,
    required this.sources,
    required this.updates,
    required this.correctionsCount,
    required this.version,
    this.headlineTe,
    this.headlineTen,
    this.headlineEn,
    this.leadTe,
    this.bodyTe,
    this.bodyTen,
    this.bodyEn,
    this.district,
    this.mandal,
    this.state,
    this.isBreaking = false,
    this.isDeveloping = false,
    this.imageUrl,
    this.publishedAt,
    this.updatedAt,
  });

  factory StoryDetail.fromJson(Map<String, dynamic> json) {
    return StoryDetail(
      id: json['id'] as int,
      clusterId: json['cluster_id'] as String,
      slug: json['slug'] as String,
      headlineTe: json['headline_te'] as String?,
      headlineTen: json['headline_ten'] as String?,
      headlineEn: json['headline_en'] as String?,
      leadTe: json['lead_te'] as String?,
      section: json['section'] as String,
      status: json['status'] as String,
      bodyTe: json['body_te'] as String?,
      bodyTen: json['body_ten'] as String?,
      bodyEn: json['body_en'] as String?,
      origin: json['origin'] as String? ?? 'automated',
      editorLocked: json['editor_locked'] as bool? ?? false,
      needsReview: json['needs_review'] as bool? ?? false,
      district: json['district'] as String?,
      mandal: json['mandal'] as String?,
      state: json['state'] as String?,
      isBreaking: json['is_breaking'] as bool? ?? false,
      isDeveloping: json['is_developing'] as bool? ?? false,
      importance: (json['importance'] as num?)?.toDouble() ?? 0.0,
      evidenceScore: (json['evidence_score'] as num?)?.toDouble() ?? 0.0,
      numSources: json['num_sources'] as int? ?? 0,
      imageUrl: json['image_url'] as String?,
      publishedAt: json['published_at'] as String?,
      updatedAt: json['updated_at'] as String?,
      facts: ((json['facts'] as List?) ?? const [])
          .map((e) => FactView.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      sources: ((json['sources'] as List?) ?? const [])
          .map((e) => SourceLinkView.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      updates: ((json['updates'] as List?) ?? const [])
          .map((e) => UpdateView.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      correctionsCount: json['corrections_count'] as int? ?? 0,
      version: json['version'] as int? ?? 1,
    );
  }

  final int id;
  final String clusterId;
  final String slug;
  final String? headlineTe;
  final String? headlineTen;
  final String? headlineEn;
  final String? leadTe;
  final String section;
  final String status;
  final String? bodyTe;
  final String? bodyTen;
  final String? bodyEn;
  final String origin;
  final bool editorLocked;
  final bool needsReview;
  final String? district;
  final String? mandal;
  final String? state;
  final bool isBreaking;
  final bool isDeveloping;
  final double importance;
  final double evidenceScore;
  final int numSources;
  final String? imageUrl;
  final String? publishedAt;
  final String? updatedAt;
  final List<FactView> facts;
  final List<SourceLinkView> sources;
  final List<UpdateView> updates;
  final int correctionsCount;
  final int version;

  /// What the desk actually has to work with, in the language being edited.
  String headlineIn(String locale) {
    switch (locale) {
      case 'en':
        return headlineEn ?? headlineTen ?? headlineTe ?? 'No headline yet';
      case 'ten':
        return headlineTen ?? headlineTe ?? headlineEn ?? 'No headline yet';
      default:
        return headlineTe ?? headlineTen ?? headlineEn ?? 'శీర్షిక లేదు';
    }
  }

  String bodyIn(String locale) {
    switch (locale) {
      case 'en':
        return bodyEn ?? '';
      case 'ten':
        return bodyTen ?? '';
      default:
        return bodyTe ?? '';
    }
  }

  /// Locked means automation will not touch this story's wording.
  bool get isManual => origin == 'manual';

  String copy() => 'Story #$id · $section · $status';
}

@immutable
class Page<T> {
  const Page({required this.items, required this.total, required this.hasMore});

  factory Page.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    return Page<T>(
      items: ((json['items'] as List?) ?? const [])
          .map((e) => fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      total: json['total'] as int? ?? 0,
      hasMore: json['has_more'] as bool? ?? false,
    );
  }

  final List<T> items;
  final int total;
  final bool hasMore;
}

@immutable
class NewsroomUser {
  const NewsroomUser({
    required this.id,
    required this.email,
    required this.role,
    this.displayName,
    this.isActive = true,
  });

  factory NewsroomUser.fromJson(Map<String, dynamic> json) {
    return NewsroomUser(
      id: json['id'] as int,
      email: json['email'] as String,
      role: json['role'] as String? ?? 'user',
      displayName: json['display_name'] as String?,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  final int id;
  final String email;
  final String role;
  final String? displayName;
  final bool isActive;

  bool get isAdmin => role == 'admin';
  bool get isEditor => role == 'admin' || role == 'editor';

  String get label => displayName?.isNotEmpty == true ? displayName! : email;
}

@immutable
class PipelineHealth {
  const PipelineHealth({
    required this.articlesFailed,
    required this.jobsStuck,
    required this.storiesNeedingReview,
    required this.storiesEditorLocked,
    required this.needsAttention,
  });

  factory PipelineHealth.fromJson(Map<String, dynamic> json) {
    return PipelineHealth(
      articlesFailed: json['articles_failed'] as int? ?? 0,
      jobsStuck: json['jobs_stuck'] as int? ?? 0,
      storiesNeedingReview: json['stories_needing_review'] as int? ?? 0,
      storiesEditorLocked: json['stories_editor_locked'] as int? ?? 0,
      needsAttention: json['needs_attention'] as bool? ?? false,
    );
  }

  final int articlesFailed;
  final int jobsStuck;
  final int storiesNeedingReview;
  final int storiesEditorLocked;
  final bool needsAttention;
}

@immutable
class FailedArticle {
  const FailedArticle({
    required this.id,
    required this.url,
    this.title,
    this.sourceId,
    this.reason,
    this.ingestedAt,
  });

  factory FailedArticle.fromJson(Map<String, dynamic> json) {
    return FailedArticle(
      id: json['id'] as int,
      url: json['url'] as String,
      title: json['title'] as String?,
      sourceId: json['source_id'] as int?,
      reason: json['reason'] as String?,
      ingestedAt: json['ingested_at'] as String?,
    );
  }

  final int id;
  final String url;
  final String? title;
  final int? sourceId;
  final String? reason;
  final String? ingestedAt;
}

@immutable
class FailedJob {
  const FailedJob({
    required this.id,
    required this.kind,
    required this.status,
    this.attempts = 0,
    this.error,
  });

  factory FailedJob.fromJson(Map<String, dynamic> json) {
    return FailedJob(
      id: json['id'] as int,
      kind: json['kind'] as String,
      status: json['status'] as String? ?? 'failed',
      attempts: json['attempts'] as int? ?? 0,
      error: json['error'] as String?,
    );
  }

  final int id;
  final String kind;
  final String status;
  final int attempts;
  final String? error;
}

@immutable
class PipelineFailures {
  const PipelineFailures({
    required this.articles,
    required this.jobs,
    required this.total,
    required this.hasMore,
  });

  factory PipelineFailures.fromJson(Map<String, dynamic> json) {
    return PipelineFailures(
      articles: ((json['articles'] as List?) ?? const [])
          .map((e) => FailedArticle.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      jobs: ((json['jobs'] as List?) ?? const [])
          .map((e) => FailedJob.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      total: json['total'] as int? ?? 0,
      hasMore: json['has_more'] as bool? ?? false,
    );
  }

  final List<FailedArticle> articles;
  final List<FailedJob> jobs;
  final int total;
  final bool hasMore;
}
