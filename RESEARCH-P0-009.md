# P0-009: MakerWorld Integration in Bambu Studio and OrcaSlicer

## Summary

MakerWorld is Bambu Lab's model-sharing platform (https://makerworld.com). Both BambuStudio and OrcaSlicer integrate with it for:
- **Model discovery & download** from the web interface
- **Model upload/publishing** capability
- **SSO (Single Sign-On)** into MakerWorld using Bambu Studio account credentials
- **Print history** tracking (cloud-linked)
- **Model preview** and profile management

Authentication uses a **bind ticket mechanism** (proprietary, server-mediated) rather than OAuth. The flow is: Studio → NetworkAgent.request_bind_ticket() → MakerWorld api/sign-in/ticket endpoint → browser redirect with authentication.

**OrcaSlicer has stripped out the SSO webview integration** but retains model download capability via bind ticket.

---

## MakerWorld URLs and Regional Variants

### BambuStudio
File: `.research/BambuStudio/src/slic3r/GUI/GUI_App.cpp:1607-1640`

```cpp
// get_model_http_url() function
if (country_code == "US") {
    url = "https://makerworld.com/";
} else if (country_code == "CN") {
    url = "https://makerworld.com.cn/";
} else if (country_code == "ENV_CN_DEV") {
    url = "https://makerhub-dev.bambu-lab.com/";
} // else defaults to makerworld.com
```

Trusted CDN domains (line 1131-1137):
- `public-cdn.bblmw.com` (no HTTPS requirement)
- `makerworld.bblmw.cn` (China CDN, no HTTPS requirement)
- `makerworld.bblmw.com` (Global CDN, no HTTPS requirement)
- `or-cloud-makerlab-prod.s3-accelerate.amazonaws.com` (AWS S3)
- `sh-makerlab-prod.oss-cn-shanghai.aliyuncs.com` (Alibaba OSS China)

### OrcaSlicer
File: `.research/OrcaSlicer/src/slic3r/GUI/GUI_App.cpp:1304-1323`

Same URLs, but **no regional CN.CN variant**—both US and CN default to `https://makerworld.com/` (not .cn).

---

## Authentication Flow: Bind Ticket Mechanism

### How it Works

**File:** `.research/BambuStudio/src/slic3r/Utils/NetworkAgent.cpp:1441-1450`

```cpp
int NetworkAgent::request_bind_ticket(std::string* ticket) {
    int ret = 0;
    if (network_agent && request_bind_ticket_ptr) {
        ret = request_bind_ticket_ptr(network_agent, ticket);  // calls native bambu_network library
        if (ret)
            BOOST_LOG_TRIVIAL(error) << "error acquiring bind ticket";
    }
    return ret;
}
```

The `request_bind_ticket()` is a **wrapper around a native C library function** (`bambu_network_request_bind_ticket`) loaded dynamically from the Bambu Network plugin (`libslic3r/Utils/NetworkAgent.cpp:369`). The actual implementation lives in the closed-source **BambuNetworking plugin**, not in the Studio source code.

### Sign-In Flow

**Files:**
- `.research/BambuStudio/src/slic3r/GUI/GUI_App.cpp:7997-8021` (open_makerworld_page_dialog)
- `.research/BambuStudio/src/slic3r/GUI/GUI_App.cpp:8038-8056` (open_publish_page_dialog)
- `.research/BambuStudio/src/slic3r/GUI/WebViewDialog.cpp:1330-1415` (SSO navigation logic)

Steps:

1. **User is logged into Studio**: `if (getAgent()->is_user_login())`
2. **Request bind ticket**: `result = getAgent()->request_bind_ticket(&ticket);`
3. **Build sign-in URL**: 
   ```cpp
   link_url = host_url + "api/sign-in/ticket?to=" + url_encode(model_url) + "&ticket=" + ticket;
   // e.g.: https://makerworld.com/api/sign-in/ticket?to=...&ticket=ABC123
   ```
4. **Navigate browser**: The ticket is passed to MakerWorld, which validates it server-side and logs the user in.
5. **Redirect**: User lands on the target page (model detail, publish page, etc.) already authenticated.

### Key Distinction: Not OAuth

- **No public OAuth flow exists**. The bind ticket is a private Bambu Lab mechanism.
- **Not JWT-based in the Studio → API direction**. Instead, it's a session token exchange (ticket → server-side session).
- **Proprietary server-mediated auth**. Bambu Lab controls both the client (Studio) and server (MakerWorld), so they don't expose a public OAuth spec.

---

## Features Integrated in BambuStudio

### 1. Model Download from MakerWorld

**File:** `.research/BambuStudio/src/slic3r/GUI/GUI_App.cpp:5244-5254`

```cpp
else if (command_str.compare("makerworld_model_open") == 0) {
    if (root.get_child_optional("model") != boost::none) {
        pt::ptree data_node = root.get_child("model");
        boost::optional<std::string> path = data_node.get_optional<std::string>("url");
        if (path.has_value()) {
            wxString realurl = from_u8(url_decode(path.value()));
            wxGetApp().request_model_download(realurl);  // triggers model import UI
        }
    }
}
```

- JavaScript running in the MakerWorld webview sends a `makerworld_model_open` command with a model URL.
- Studio's `handle_web_request()` intercepts this, decodes the URL, and triggers the Plater's download/import dialog.
- The URL points to a CDN (one of the trusted domains listed above).

### 2. WebView SSO Integration (BambuStudio Only)

**Files:**
- `.research/BambuStudio/src/slic3r/GUI/WebViewDialog.hpp:187-190` (SSO state vars)
- `.research/BambuStudio/src/slic3r/GUI/WebViewDialog.cpp:717-722` (SSO timeout)
- `.research/BambuStudio/src/slic3r/GUI/WebViewDialog.cpp:1330-1415` (SSO navigation)

BambuStudio hosts **three separate webviews** in the main window:
1. `m_browser` — Home/homepage
2. `m_browserMW` — MakerWorld webview (embedded in `m_online_container`)
3. `m_browserML` — MakerLab webview (embedded in `m_online_container`)

When user navigates to MakerWorld tab:
- `UpdateMakerworldLoginStatus()` is called (line 738)
- `SetMakerworldModelID()` stores the model ID if opening from a link (line 5003)
- SSO flow initiates: `request_bind_ticket()` → `api/sign-in/ticket` URL → browser loads it with token
- **SSO has a 15-second timeout** (line 718): if navigation doesn't complete, it's logged as an error and retried.

### 3. Model Publishing

**File:** `.research/BambuStudio/src/slic3r/GUI/GUI_App.cpp:8023-8056`

```cpp
void GUI_App::open_publish_page_dialog() {
    // ... same bind ticket flow as open_makerworld_page_dialog() ...
    link_url = host_url + "api/sign-in/ticket?to=" + url_encode(model_url) + "&ticket=" + ticket;
    // Launches browser to: /en/my/models/publish (or localized variant)
}
```

Users can publish models directly to MakerWorld from Studio.

### 4. Print History Integration

**File:** `.research/BambuStudio/src/slic3r/GUI/WebViewDialog.hpp:274-281`

- A fourth webview (`m_browserPH`) displays cloud-linked print history.
- User must be logged in (`wxGetApp().is_user_login()`).
- Bind ticket is requested for this webview as well.

---

## OrcaSlicer: Stripped SSO, Kept Downloads

### What OrcaSlicer Removed

**File:** `.research/OrcaSlicer/src/slic3r/GUI/WebViewDialog.cpp` (searched for `m_makerworld_sso*` → **no matches**)
**File:** `.research/OrcaSlicer/src/slic3r/GUI/WebViewDialog.hpp` (no SSO state variables)

OrcaSlicer **does not embed MakerWorld or MakerLab webviews** in the UI. No SSO flow, no browser-based integration.

### What OrcaSlicer Kept

**File:** `.research/OrcaSlicer/src/slic3r/GUI/GUI_App.cpp:5534-5544`

```cpp
else if (command_str.compare("makerworld_model_open") == 0) {
    if (root.get_child_optional("model") != boost::none) {
        pt::ptree data_node = root.get_child("model");
        boost::optional<std::string> path = data_node.get_optional<std::string>("url");
        if (path.has_value()) {
            wxString realurl = from_u8(url_decode(path.value()));
            wxGetApp().request_model_download(realurl);
        }
    }
}
```

- **Still has the `makerworld_model_open` command handler**.
- **Still has `request_bind_ticket()`** for opening MakerWorld in external browser:

**.research/OrcaSlicer/src/slic3r/GUI/GUI_App.cpp** (grep output shows usage in `open_makerworld_page_dialog()`):
```
link_url = host_url + "api/sign-in/ticket?to=" + host_url + url_encode(model_url) + "&ticket=" + ticket;
```

So OrcaSlicer:
- **Redirects MakerWorld links to the external default browser** (not embedded).
- **Still authenticates via bind ticket** when opening MakerWorld externally.
- **Supports model download** via the same CDN domains.

---

## Account-Gating and Optional Features

| Feature | Account Required? | Guarded How? |
|---------|------------------|--------------|
| **Browse public models in MakerWorld** | No (public site) | Not gated in UI, but platform-level access |
| **Download public models** | No | Not gated; URLs are public CDN links |
| **Download private/own designs** | Yes | Requires login before accessing model detail; CDN URLs are token-less but permission-checked server-side |
| **Upload/Publish models** | Yes | Bind ticket needed; button only shown to logged-in users |
| **Print history** | Yes | Webview embedded only if `is_user_login()` → hidden otherwise |
| **Synced print profiles** | Yes | `is_user_login()` check |

**In short:** Basic model browsing/download is **not account-gated** (because the CDN links are public), but **publishing and personal content require login**.

---

## Licensing & ToS Risk for Reimplementation

### Closed-Source API

The `api/sign-in/ticket` endpoint and bind ticket mechanism are **proprietary Bambu Lab APIs**:
- Not publicly documented.
- Endpoint contract not specified (no OpenAPI spec, no RFC).
- Endpoint could change, rate-limit, or block unauthorized clients without notice.
- Bambu Lab could require authentication (API key) for this endpoint at any time.

### ToS Risk

Reimplementing MakerWorld integration would require:

1. **Reverse-engineering the bind ticket protocol** (in `libslic3r` or a custom auth module).
2. **Calling undocumented Bambu Lab endpoints** (`api/sign-in/ticket`, possibly others for model metadata).
3. **Storing/handling user credentials** (Bambu account login) in custom code.

**Bambu Lab Terms of Service likely prohibit this:**
- Unauthorized use of APIs.
- Reverse-engineering authentication.
- Scraping or re-hosting MakerWorld content.

**Relicensing risk:** Even if AGPLv3 is accepted for this project, reimplementing MakerWorld integration as a core feature could trigger a cease-and-desist from Bambu Lab (as they do own the copyright on all MakerWorld content and the platform).

### Recommendation

- **Keep MakerWorld integration optional / delegated to external browser** (like OrcaSlicer does).
- **Do not embed bind ticket auth in core slicing code**.
- **Direct users to makerworld.com in an external browser** for model discovery and publish workflows.
- **Model *download* URLs** (the CDN links) are safe to support if they're already public/posted by MakerWorld itself.

---

## File Paths and Evidence

### BambuStudio

- **Auth flow entry:** `.research/BambuStudio/src/slic3r/GUI/GUI_App.cpp:8001-8020` (open_makerworld_page_dialog)
- **WebView integration:** `.research/BambuStudio/src/slic3r/GUI/WebViewDialog.cpp:252-258` (init m_browserMW)
- **SSO state machine:** `.research/BambuStudio/src/slic3r/GUI/WebViewDialog.hpp:187-190`
- **Command handler:** `.research/BambuStudio/src/slic3r/GUI/GUI_App.cpp:5244-5254` (makerworld_model_open)
- **Bind ticket wrapper:** `.research/BambuStudio/src/slic3r/Utils/NetworkAgent.cpp:1441-1450`
- **URLs:** `.research/BambuStudio/src/slic3r/GUI/GUI_App.cpp:1607-1640`
- **Trusted CDNs:** `.research/BambuStudio/src/slic3r/GUI/GUI_App.cpp:1131-1137`
- **Translation strings (archived):** `.research/BambuStudio/bbl/i18n/zh_CN/BambuStudio_zh_CN.po:23967` (mentions "share in makerworld")

### OrcaSlicer

- **Model download handler:** `.research/OrcaSlicer/src/slic3r/GUI/GUI_App.cpp:5534-5544`
- **URLs (same as Studio):** `.research/OrcaSlicer/src/slic3r/GUI/GUI_App.cpp:1304-1323`
- **Bind ticket usage:** `.research/OrcaSlicer/src/slic3r/GUI/GUI_App.cpp` (grep output shows api/sign-in/ticket usage)
- **No WebView integration:** No `m_makerworld_sso*` vars in WebViewDialog.hpp
- **Archived i18n:** `.research/OrcaSlicer/localization/i18n/ca/OrcaSlicer_ca.po:34480` (mentions "Associate OrcaSlicer with bambustudio:// links" — feature dropped)

---

## Summary Table

| Aspect | BambuStudio | OrcaSlicer |
|--------|-------------|-----------|
| **MakerWorld WebView embedded** | Yes (m_browserMW in UI) | No |
| **SSO via bind ticket** | Yes (m_makerworld_sso_*) | No SSO UI; external browser only |
| **Model download support** | Yes (makerworld_model_open handler) | Yes (same handler) |
| **Model publish UI** | Yes (open_publish_page_dialog) | Likely yes (function exists) |
| **Print history tab** | Yes (m_browserPH) | Unclear (check WebViewDialog) |
| **Auth mechanism** | Proprietary bind ticket + api/sign-in/ticket | Proprietary bind ticket + api/sign-in/ticket |
| **Regional URLs** | makerworld.com & makerworld.com.cn | Only makerworld.com |
| **License risk** | Medium (embeds undocumented API) | Low (external browser redirect) |

