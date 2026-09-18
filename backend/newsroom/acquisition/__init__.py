"""The acquisition layer: how the newsroom reaches its sources.

Everything outbound and source-specific lives here rather than in the pipeline,
so that the pipeline stays a set of editorial decisions about *content* and
never has to know whether an outlet was read from RSS, fetched over plain HTTP,
or rendered in a browser.

The layering, deliberately:

    RSS / Atom            > the outlet's own machine interface; always preferred
    plain HTTP (httpx)    > server-rendered HTML, no extra dependency
    Scrapling Fetcher     > an outlet that refuses Python TLS fingerprints
    browser rendering     > only where the page is genuinely JavaScript-built

A source picks its adapter with ``Source.kind`` and its transport with
``Source.fetch_backend``. Neither choice is global, and neither is required: the
newsroom boots and runs a full sweep with none of the optional extras installed.
"""
