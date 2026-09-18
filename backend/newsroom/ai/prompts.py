"""Prompt templates for the newsroom stages.

Kept separate from the providers so prompt content can be reviewed and tested
independently of the transport. Every prompt enforces the product's editorial
contract: original prose, attributed claims, no invention, no copying.
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional

EDITORIAL_CONTRACT = """
EDITORIAL CONTRACT (non-negotiable):
- Write ORIGINAL sentences. Never copy more than ~15 consecutive words from a
  source, and only inside quotation marks with attribution.
- Every claim must be attributable to one of the listed sources. If you are not
  sure, mark the claim "unverified" instead of stating it.
- Never invent names, numbers, dates, places, quotes or outcomes.
- Never state an opinion as fact. Label opinion as opinion.
- Distinguish: fact / official statement / claim / allegation / forecast /
  opinion / unverified report.
- Write only what the requested format asks for. No preamble, no meta comments.
"""


def _source_block(facts: List[Dict[str, Any]]) -> str:
    lines: List[str] = []
    for index, fact in enumerate(facts, start=1):
        lines.append(
            f"[S{index}] {fact.get('source_name', 'Unknown')} "
            f"({fact.get('published', 'unknown time')}): {fact.get('title', '')}\n"
            f"      {fact.get('text', '')[:1200]}"
        )
    return "\n".join(lines) or "(no source material available)"


def headline_prompt(facts: List[Dict[str, Any]], language: str,
                    district: Optional[str]) -> str:
    lang_name = {"te": "Telugu script", "ten": "Tenglish (Telugu in Latin letters)",
                 "en": "English"}.get(language, "English")
    return f"""{EDITORIAL_CONTRACT}

Write ONE news headline for the Dasha News mobile front page.

Language: {lang_name}
Story location: {district or "Telangana (state level)"}

Rules:
- Maximum 9 words, informative, no clickbait, no exclamation marks.
- State the event and the place. Do not sensationalise.
- Do not quote a source headline verbatim.

SOURCE MATERIAL:
{_source_block(facts)}

Reply with the headline only, on one line."""


def article_prompt(facts: List[Dict[str, Any]], language: str,
                   headline: Optional[str], district: Optional[str],
                   max_words: int = 180) -> str:
    lang_name = {"te": "Telugu script", "ten": "Tenglish (Telugu in Latin letters)",
                 "en": "English"}.get(language, "English")
    return f"""{EDITORIAL_CONTRACT}

Write a Dasha News article body in {lang_name}, {max_words} words or fewer.

Structure:
1. One lead sentence answering who/what/where/when.
2. Two to four short paragraphs developing the story from the sources below.
3. Attribution inline ("according to [S1]") wherever a claim is not an
   established fact.
4. Where sources disagree, state both sides with their attribution.

Headline to develop from: {headline or '(none yet)'}
Location: {district or "Telangana"}

SOURCE MATERIAL:
{_source_block(facts)}

Reply with the article body only. No headline, no byline, no commentary."""


def fact_prompt(text: str, source_name: str) -> str:
    return f"""{EDITORIAL_CONTRACT}

Extract discrete, attributable facts from this news text. Classify each one.

Evidence levels: fact, official, claim, allegation, forecast, opinion,
unverified, disputed.

Return ONLY a JSON array, no prose:
[
  {{"text_en": "one sentence in English", "level": "official",
    "attributed_to": "who said it or which body", "confidence": 0.0-1.0}}
]

Rules:
- One fact per element. Never merge two claims.
- "confidence" is your confidence that the statement is supported by this text,
  not that the statement is true.
- If the text contains no factual claim, return [].

SOURCE: {source_name}
TEXT:
{text[:4000]}"""


def summary_prompt(text: str, language: str) -> str:
    lang_name = {"te": "Telugu script", "ten": "Tenglish (Telugu in Latin letters)",
                 "en": "English"}.get(language, "English")
    return f"""{EDITORIAL_CONTRACT}

Summarise the following text into 3 sentences in {lang_name}. Attribute
contested claims. Do not add information that is not in the text.

TEXT:
{text[:3000]}"""
