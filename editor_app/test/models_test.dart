/// Tests for the shapes the newsroom returns.
///
/// The UI renders gaps rather than inventing filler, so the fallback chains
/// here -- which language a headline falls back to, what a manual story has no
/// sources for -- are the difference between "we have not written this yet"
/// and "this story has no sources". They are the contract the desk reads.
library;

import 'package:dasha_editor/models/story.dart';
import 'package:flutter_test/flutter_test.dart';

StoryDetail _story({
  String? headlineTe,
  String? headlineTen,
  String? headlineEn,
  String? bodyTe,
  String? bodyTen,
  String? bodyEn,
  String origin = 'automated',
  bool editorLocked = false,
}) {
  return StoryDetail.fromJson({
    'id': 42,
    'cluster_id': 'c-1',
    'slug': 'hyderabad-rains',
    'section': 'general',
    'status': 'draft',
    'origin': origin,
    'editor_locked': editorLocked,
    'needs_review': true,
    'num_sources': 3,
    'importance': 0.8,
    'evidence_score': 0.66,
    'headline_te': ?headlineTe,
    'headline_ten': ?headlineTen,
    'headline_en': ?headlineEn,
    'body_te': ?bodyTe,
    'body_ten': ?bodyTen,
    'body_en': ?bodyEn,
  });
}

void main() {
  // --------------------------------------------------------------------------
  // Headlines: the desk's fallback chain
  // --------------------------------------------------------------------------

  test('Telugu is the floor of every language the desk writes', () {
    final story = _story(headlineTe: 'హైదరాబాద్ వరదలు');
    expect(story.headlineIn('te'), 'హైదరాబాద్ వరదలు');
    // The other two editions fall back to Telugu rather than to nothing.
    expect(story.headlineIn('ten'), 'హైదరాబాద్ వరదలు');
    expect(story.headlineIn('en'), 'హైదరాబాద్ వరదలు');
  });

  test('Tenglish falls back to Telugu before it falls back to English', () {
    final story = _story(headlineTe: 'తెలుగు శీర్షిక', headlineEn: 'English headline');
    expect(story.headlineIn('ten'), 'తెలుగు శీర్షిక');
    expect(story.headlineIn('en'), 'English headline');
  });

  test('English falls back to Tenglish when that is what the desk wrote', () {
    final story = _story(headlineTen: 'Hyderabad lo varadalu');
    expect(story.headlineIn('en'), 'Hyderabad lo varadalu');
  });

  test('a story with no headline at all says so instead of rendering blank', () {
    final story = _story();
    expect(story.headlineIn('te'), 'శీర్షిక లేదు');
    expect(story.headlineIn('en'), 'No headline yet');
    expect(story.headlineIn('ten'), 'No headline yet');
  });

  test('a body the desk has not written is empty, not inherited', () {
    final story = _story(bodyTe: 'వార్త వివరాలు');
    expect(story.bodyIn('te'), 'వార్త వివరాలు');
    expect(story.bodyIn('ten'), '');
    expect(story.bodyIn('en'), '');
  });

  // --------------------------------------------------------------------------
  // Origin and precedence
  // --------------------------------------------------------------------------

  test('origin is what separates an editor\'s story from a generated one', () {
    expect(_story().isManual, isFalse);
    expect(_story(origin: 'manual').isManual, isTrue);
    expect(_story(origin: 'manual', editorLocked: true).editorLocked, isTrue);
  });

  test('a story that never had fields defaults to the automation\'s origin', () {
    final minimal = StoryDetail.fromJson({
      'id': 1,
      'cluster_id': 'c-2',
      'slug': 's',
      'section': 'politics',
      'status': 'published',
    });
    expect(minimal.origin, 'automated');
    expect(minimal.editorLocked, isFalse);
    expect(minimal.needsReview, isFalse);
    expect(minimal.numSources, 0);
    expect(minimal.facts, isEmpty);
    expect(minimal.sources, isEmpty);
    expect(minimal.updates, isEmpty);
    expect(minimal.version, 1);
  });

  // --------------------------------------------------------------------------
  // Facts, sources, and the audit trail
  // --------------------------------------------------------------------------

  test('facts and sources parse, and a withdrawn fact is still recorded', () {
    final story = StoryDetail.fromJson({
      'id': 7,
      'cluster_id': 'c-3',
      'slug': 'warangal-protest',
      'section': 'politics',
      'status': 'published',
      'facts': [
        {
          'id': 1,
          'text_te': 'అధికారిక ప్రకటన',
          'text_en': 'an official statement',
          'evidence_level': 'official',
          'confidence': 0.92,
          'attributed_to': 'SP Office',
          'status': 'active',
          'rank': 0,
        },
        {
          'id': 2,
          'text_te': 'ప్రతినిధి వాదన',
          'evidence_level': 'allegation',
          'status': 'withdrawn',
          'rank': 1,
        },
      ],
      'sources': [
        {
          'id': 10,
          'source_name': 'Telangana Today',
          'article_url': 'https://example.news/a',
          'corroborates': true,
        },
        {
          'id': 11,
          'source_name': 'A competing wire',
          'article_url': 'https://other.news/b',
          'conflicts_with': 'Fact 1',
        },
      ],
      'updates': [
        {
          'id': 5,
          'kind': 'publish',
          'created_at': '2026-09-18T09:00:00Z',
          'applied_by': 'owner@example.news',
        },
        {
          'id': 6,
          'kind': 'correct',
          'created_at': '2026-09-18T10:00:00Z',
          'headline': 'Correction',
          'text_te': 'సవరణ',
        },
      ],
      'corrections_count': 1,
    });

    expect(story.facts.length, 2);
    final live = story.facts.singleWhere((f) => f.isActive);
    final withdrawn = story.facts.singleWhere((f) => !f.isActive);
    expect(live.evidenceLevel, 'official');
    expect(live.confidence, closeTo(0.92, 1e-6));
    expect(live.attributedTo, 'SP Office');
    expect(withdrawn.evidenceLevel, 'allegation');

    final corroborated = story.sources.singleWhere((s) => s.corroborates);
    final conflicting = story.sources.singleWhere((s) => !s.corroborates);
    expect(corroborated.sourceName, 'Telangana Today');
    expect(conflicting.conflictsWith, 'Fact 1');

    expect(story.updates.map((u) => u.kind), ['publish', 'correct']);
    expect(story.correctionsCount, 1);
  });

  // --------------------------------------------------------------------------
  // Paging
  // --------------------------------------------------------------------------

  test('a page reports whether there is more to load', () {
    final full = Page.fromJson({
      'items': [
        {'id': 1, 'cluster_id': 'c', 'slug': 'a', 'section': 's', 'status': 'draft'}
      ],
      'total': 40,
      'has_more': true,
    }, StoryDetail.fromJson);
    expect(full.items.single.id, 1);
    expect(full.total, 40);
    expect(full.hasMore, isTrue);

    final empty = Page.fromJson({}, StoryDetail.fromJson);
    expect(empty.items, isEmpty);
    expect(empty.total, 0);
    expect(empty.hasMore, isFalse);
  });

  test('a user is an editor if the newsroom said so, and not otherwise', () {
    expect(NewsroomUser(id: 1, email: 'a@b.c', role: 'admin').isAdmin, isTrue);
    expect(NewsroomUser(id: 2, email: 'b@b.c', role: 'editor').isEditor, isTrue);
    expect(NewsroomUser(id: 3, email: 'c@b.c', role: 'user').isEditor, isFalse);
    expect(NewsroomUser(id: 3, email: 'c@b.c', role: 'user').isAdmin, isFalse);
  });

  test('a display name is preferred, but an empty one is not', () {
    expect(
        NewsroomUser(id: 1, email: 'a@b.c', role: 'editor', displayName: 'The Desk')
            .label,
        'The Desk');
    expect(NewsroomUser(id: 1, email: 'a@b.c', role: 'editor', displayName: '').label,
        'a@b.c');
    expect(NewsroomUser(id: 1, email: 'a@b.c', role: 'user').label, 'a@b.c');
  });

  test('a suspended account keeps its role and loses its access flag', () {
    final suspended = NewsroomUser.fromJson(
        {'id': 4, 'email': 'd@b.c', 'role': 'editor', 'is_active': false});
    expect(suspended.role, 'editor');
    expect(suspended.isActive, isFalse);
  });

  test('pipeline health and failures default to zero when nothing has run', () {
    final health = PipelineHealth.fromJson({});
    expect(health.articlesFailed, 0);
    expect(health.jobsStuck, 0);
    expect(health.needsAttention, isFalse);

    final failures = PipelineFailures.fromJson({});
    expect(failures.articles, isEmpty);
    expect(failures.jobs, isEmpty);
    expect(failures.total, 0);
  });

  test('a failed article keeps the reason it failed', () {
    final article = FailedArticle.fromJson({
      'id': 9,
      'url': 'https://example.news/blocked',
      'title': 'A blocked story',
      'reason': '403 after retry',
      'ingested_at': '2026-09-18T08:00:00Z',
    });
    expect(article.url, 'https://example.news/blocked');
    expect(article.reason, '403 after retry');

    final job = FailedJob.fromJson({'id': 3, 'kind': 'summarize', 'attempts': 4});
    expect(job.kind, 'summarize');
    expect(job.status, 'failed');
    expect(job.attempts, 4);
  });
}
