# Phase 5 model-repository audit

**Date:** 2026-10-16
**Question:** Which model repositories expose documented APIs suitable for a native integration, rather than relying on an external browser window?

## Result

MakerWorld browser delegation remains a deliberately narrow safety measure, **not** authentication, in-app browsing, or downloadable-model integration. Its bind-ticket SSO is implemented only in Bambu's closed `bambu_networking` binary (`RESEARCH-P0-009.md:48-83`); no public authentication or download API exists to implement safely.

| Repository | Evidence | Search/metadata | Authorized download | Decision |
|---|---|---:|---:|---|
| MakerWorld | Proprietary bind-ticket wrapper (`NetworkAgent.cpp:1441-1450`); no public API | no | no | Browser handoff only; does not satisfy P5 auth/browse/download. |
| Thingiverse | [Developer Swagger](https://www.thingiverse.com/developers/swagger) and legacy REST API | documented | documented for authenticated clients | Not selected: `api.thingiverse.com` returned a Cloudflare challenge (not JSON/401) from this environment on 2026-10-16. Do not bypass the challenge. |
| Printables | [Prusa staff: GraphQL exists but is undocumented](https://forum.prusa3d.com/forum/general-discussion-user-experience-ideas/is-there-a-publicly-available-rest-api/) | unofficial only | unofficial only | Rejected: implementing against a private GraphQL endpoint would repeat the MakerWorld ToS/stability risk. |
| Cults3D | [Official GraphQL API](https://cults3d.com/en/pages/graphql) | documented | API exposes catalog metadata, not download files | Not selected: insufficient for the Import workflow. |
| **MyMiniFactory** | [Official OpenAPI spec](https://github.com/MyMiniFactory/api-documentation/blob/master/myminifactory-api.yaml) + [official OAuth instructions](https://github.com/MyMiniFactory/api-documentation/blob/master/oauth2-instructions.md) | **yes** (`GET /api/v2/search`, `/objects/{id}/files`) | **yes**, OAuth `download_url`/`archive_download_url` | Selected. Implemented API-key search plus documented OAuth authorization-code download/import flow. |

## MyMiniFactory contract used

The actual published spec (fetched directly from `raw.githubusercontent.com/MyMiniFactory/api-documentation/master/myminifactory-api.yaml` during this audit) documents:

- Production base URL: `https://www.myminifactory.com/api/v2`.
- `GET /search?q=...`, with either OAuth or query API-key authentication (`key`).
- `GET /objects/{object_id}/files`.
- `Object.archive_download_url` and `File.download_url`: **“Available ONLY with Oauth connected User. Not with API key.”**
- Authorization-code grant: `https://auth.myminifactory.com/web/authorize`; code exchange at `POST https://auth.myminifactory.com/v1/oauth/tokens` using HTTP Basic client credentials and form values `grant_type=authorization_code`, `code`, and the registered `redirect_uri`.

NativeSlicerA1 therefore does not claim an API key can download models. `MyMiniFactoryClient.downloadFile` refuses a file with no OAuth-only `download_url`; `MyMiniFactoryView` tells the user why and offers real OAuth setup rather than a browser workaround.

## Implementation and verification boundary

Implemented code:

- `MyMiniFactoryClient.swift`: documented API requests, decoding, OAuth bearer downloads, and code-token exchange.
- `MyMiniFactoryAuth.swift`: `ASWebAuthenticationSession` authorization-code flow; client credentials/tokens live in the macOS Keychain only.
- `MyMiniFactoryView.swift`: in-app search, file selection, and direct STL/3MF import through `ProjectDocument.importModel`.
- `Resources/Info.plist`: declares `nativeslicera1://` for the OAuth callback and is embedded in the executable by `Package.swift`.

The API's live calls could not be verified from this environment: unauthenticated `curl` to MyMiniFactory search returned HTTP 403 with `cf-mitigated: challenge`; Thingiverse returned Cloudflare's HTML challenge. The implementation's request/response logic is covered by mocked transport regression tests, but live API and OAuth GUI verification require a user-created MyMiniFactory OAuth client and a packaged, Launch-Services-registered `.app`. P8-006 owns production `.app` packaging. This is an explicit verification boundary, not a claim that browser delegation or mocked calls prove a live repository integration.
