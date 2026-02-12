defmodule Fireauth.Snippets do
  @moduledoc """
  Small HEEx-friendly snippets for wiring Fireauth client-side flows without
  requiring a bundler integration.

  This module returns `Phoenix.HTML.Safe` values (HTML) that can be embedded
  directly in templates.

  It depends only on `phoenix_html` (not `phoenix`), so it can be used anywhere
  HEEx is available.
  """

  @type client_opts :: [
          return_to: String.t(),
          session_base: String.t(),
          require_verified: boolean(),
          debug: boolean()
        ]

  @doc """
  Embed Fireauth's minimal client API directly in the page.

  Public API on `window.fireauth`:

  - `start(opts, callback)`
    - stores localStorage markers
    - runs your callback to start Firebase redirect

  - `verify(opts, callback)`
    - checks localStorage markers
    - resolves id token
    - exchanges id token for session cookie
    - redirects to `return_to`
    - returns chain handlers: `.success(...).error(...).onStateChange(...)`

  Token resolution for `verify`:

  - `opts.getIdToken(context)`

  Options:
  - `:return_to` - internal path to navigate to after session is established (default: `"/"`)
  - `:session_base` - mount path for `Fireauth.Plug.SessionRouter` (default: `"/auth/firebase"`)
  - `:require_verified` - require verified email in verify flow (default: true)
  - `:debug` - enable console logging (default: false)
  """
  @spec client(client_opts()) :: Phoenix.HTML.safe()
  def client(opts) when is_list(opts) do
    return_to = Keyword.get(opts, :return_to, "/")
    session_base = Keyword.get(opts, :session_base, "/auth/firebase")
    require_verified = Keyword.get(opts, :require_verified, true)
    debug = Keyword.get(opts, :debug, false)

    html = """
    <script>
      (function () {
        var defaults = {
          returnTo: "#{h(return_to)}",
          sessionBase: "#{h(session_base)}",
          requireVerified: #{if(require_verified, do: "true", else: "false")},
          debug: #{if(debug, do: "true", else: "false")}
        };

        var STARTED_KEY = "fireauth.started.v1";
        var PROVIDER_KEY = "fireauth.provider_id.v1";
        var RETURN_TO_KEY = "fireauth.return_to.v1";
        var SESSION_BASE_KEY = "fireauth.session_base.v1";

        function safeCall(cb, value) {
          try { cb(value); } catch (_e) {}
        }

        function safeGet(key) {
          try { return window.localStorage.getItem(key); } catch (_e) { return null; }
        }

        function safeSet(key, value) {
          try { window.localStorage.setItem(key, value); } catch (_e) {}
        }

        function safeRemove(key) {
          try { window.localStorage.removeItem(key); } catch (_e) {}
        }

        function sanitizeReturnToPath(path) {
          if (!path) return "/";
          if (!path.startsWith("/")) return "/";
          if (path.startsWith("//")) return "/";
          return path;
        }

        function isJwt(token) {
          return typeof token === "string" && token.split(".").length === 3;
        }

        var fw = (window.fireauth = window.fireauth || {});
        fw._defaults = Object.assign(
          { returnTo: "/", sessionBase: "/auth/firebase", requireVerified: true, debug: false },
          fw._defaults || {},
          defaults
        );
        fw._lastState = fw._lastState || null;
        fw._stateListeners = fw._stateListeners || new Set();
        fw._errorListeners = fw._errorListeners || new Set();
        fw._successListeners = fw._successListeners || new Set();

        function log(level, message, meta) {
          if (!fw._defaults.debug) return;
          var prefix = "[fireauth]";
          try {
            if (level === "error") console.error(prefix, message, meta || "");
            else if (level === "warn") console.warn(prefix, message, meta || "");
            else if (level === "info") console.info(prefix, message, meta || "");
            else console.debug(prefix, message, meta || "");
          } catch (_e) {}
        }

        function makeChain() {
          var chain = {
            _state: [],
            _error: [],
            _success: [],
            onStateChange: function (cb) {
              if (typeof cb === "function") {
                chain._state.push(cb);
                if (fw._lastState) safeCall(cb, fw._lastState);
              }
              return chain;
            },
            error: function (cb) {
              if (typeof cb === "function") {
                chain._error.push(cb);
                if (fw._lastState && fw._lastState.type === "error") safeCall(cb, fw._lastState);
              }
              return chain;
            },
            success: function (cb) {
              if (typeof cb === "function") {
                chain._success.push(cb);
                if (fw._lastState && fw._lastState.type === "success") safeCall(cb, fw._lastState);
              }
              return chain;
            }
          };

          return chain;
        }

        function notify(chain, state) {
          fw._lastState = state;

          fw._stateListeners.forEach(function (cb) { safeCall(cb, state); });
          if (state.type === "error") fw._errorListeners.forEach(function (cb) { safeCall(cb, state); });
          if (state.type === "success") fw._successListeners.forEach(function (cb) { safeCall(cb, state); });

          if (!chain) return;
          chain._state.forEach(function (cb) { safeCall(cb, state); });
          if (state.type === "error") chain._error.forEach(function (cb) { safeCall(cb, state); });
          if (state.type === "success") chain._success.forEach(function (cb) { safeCall(cb, state); });
        }

        function baseState(mode, providerId, returnTo, sessionBase) {
          return {
            ts: Date.now(),
            mode: mode,
            providerId: providerId || "",
            returnTo: sanitizeReturnToPath(returnTo || "/"),
            sessionBase: sessionBase || "/auth/firebase"
          };
        }

        function publishLoading(chain, base, stage, message, extra) {
          notify(
            chain,
            Object.assign({}, base, {
              type: "loading",
              loading: true,
              stage: stage,
              message: message
            }, extra || {})
          );
        }

        function publishError(chain, base, stage, code, message) {
          notify(
            chain,
            Object.assign({}, base, {
              type: "error",
              loading: false,
              stage: stage,
              code: code,
              message: message
            })
          );
        }

        function publishSuccess(chain, base, stage, extra) {
          notify(
            chain,
            Object.assign({}, base, {
              type: "success",
              loading: false,
              stage: stage
            }, extra || {})
          );
        }

        function setFlowMarkers(providerId, returnTo, sessionBase) {
          safeSet(STARTED_KEY, "1");
          safeSet(PROVIDER_KEY, providerId || "");
          safeSet(RETURN_TO_KEY, sanitizeReturnToPath(returnTo || "/"));
          safeSet(SESSION_BASE_KEY, sessionBase || "/auth/firebase");
        }

        function clearFlowMarkers() {
          safeRemove(STARTED_KEY);
          safeRemove(PROVIDER_KEY);
          safeRemove(RETURN_TO_KEY);
          safeRemove(SESSION_BASE_KEY);
        }

        async function exchangeIdTokenForCookie(sessionBase, idToken) {
          var csrfResp = await fetch(sessionBase + "/csrf", { credentials: "same-origin" });
          if (!csrfResp.ok) throw new Error("csrf failed: " + csrfResp.status);

          var csrfJson = await csrfResp.json();
          var csrfToken = csrfJson && csrfJson.csrfToken;
          if (!csrfToken) throw new Error("csrf missing token");

          var sessionResp = await fetch(sessionBase + "/session", {
            method: "POST",
            credentials: "same-origin",
            headers: {
              "content-type": "application/json",
              "x-csrf-token": csrfToken
            },
            body: JSON.stringify({ idToken: idToken, csrfToken: csrfToken })
          });

          if (!sessionResp.ok) {
            var body = "";
            try { body = await sessionResp.text(); } catch (_e) {}
            throw new Error("session failed: " + sessionResp.status + " " + body);
          }
        }

        async function resolveCurrentUser(input, context) {
          if (typeof input.getAuth === "function") {
            console.log("found getAuth", input.getAuth());
            const auth = input.getAuth();

            await auth.authStateReady();
            console.log(auth.currentUser);

            return auth.currentUser;
          }

          return null;
        }

        if (typeof fw.onStateChange !== "function") {
          fw.onStateChange = function (cb, opts) {
            if (typeof cb !== "function") return function () {};
            fw._stateListeners.add(cb);
            var immediate = !(opts && opts.immediate === false);
            if (immediate && fw._lastState) safeCall(cb, fw._lastState);
            return function () { fw._stateListeners.delete(cb); };
          };
        }

        if (typeof fw.onError !== "function") {
          fw.onError = function (cb, opts) {
            if (typeof cb !== "function") return function () {};
            fw._errorListeners.add(cb);
            var immediate = !!(opts && opts.immediate);
            if (immediate && fw._lastState && fw._lastState.type === "error") safeCall(cb, fw._lastState);
            return function () { fw._errorListeners.delete(cb); };
          };
        }

        if (typeof fw.onSuccess !== "function") {
          fw.onSuccess = function (cb, opts) {
            if (typeof cb !== "function") return function () {};
            fw._successListeners.add(cb);
            var immediate = !!(opts && opts.immediate);
            if (immediate && fw._lastState && fw._lastState.type === "success") safeCall(cb, fw._lastState);
            return function () { fw._successListeners.delete(cb); };
          };
        }

        fw.start = function (opts, callback) {
          var input = (opts && typeof opts === "object") ? opts : {};
          var providerId = input.provider || input.providerId || "";
          var returnTo = sanitizeReturnToPath(input.returnTo || fw._defaults.returnTo || "/");
          var sessionBase = input.sessionBase || fw._defaults.sessionBase || "/auth/firebase";
          var startFn =
            (typeof callback === "function" && callback) ||
            (typeof input.callback === "function" && input.callback) ||
            null;

          var chain = makeChain();
          var base = baseState("start", providerId, returnTo, sessionBase);

          publishLoading(chain, base, "start_init", "Preparing sign-in...");

          if (!providerId) {
            publishError(chain, base, "start_no_provider", "no_provider", "No provider configured.");
            return chain;
          }

          if (typeof startFn !== "function") {
            publishError(
              chain,
              base,
              "start_not_configured",
              "start_not_configured",
              "Missing start callback. Call fireauth.start(opts, callback)."
            );
            return chain;
          }

          setFlowMarkers(providerId, returnTo, sessionBase);
          publishLoading(chain, base, "start_redirecting", "Redirecting to provider...");

          Promise.resolve()
            .then(function () {
              return startFn(providerId, {
                providerId: providerId,
                returnTo: returnTo,
                sessionBase: sessionBase
              });
            })
            .then(function () {
              publishSuccess(chain, base, "start_dispatched", { message: "Redirect dispatched." });
            })
            .catch(function (err) {
              clearFlowMarkers();
              log("error", "start failed", err);
              publishError(
                chain,
                base,
                "start_failed",
                "start_failed",
                "Sign-in failed: " + String((err && err.message) || err)
              );
            });

          return chain;
        };

        fw.verify = function (opts, callback) {
          var input = (opts && typeof opts === "object") ? opts : {};
          var chain = makeChain();

          if (typeof callback === "function") {
            chain.onStateChange(function (state) {
              safeCall(callback, state);
            });
          }

          var started = safeGet(STARTED_KEY) === "1";
          if (!started) {
            publishError(
              chain,
              baseState("verify", "", fw._defaults.returnTo, fw._defaults.sessionBase),
              "verify_missing_start",
              "missing_start",
              "Missing local auth marker. Start sign-in again."
            );
            return chain;
          }

          var providerId = safeGet(PROVIDER_KEY) || input.provider || input.providerId || "";
          var returnTo = sanitizeReturnToPath(
            safeGet(RETURN_TO_KEY) || input.returnTo || fw._defaults.returnTo || "/"
          );
          var sessionBase =
            safeGet(SESSION_BASE_KEY) || input.sessionBase || fw._defaults.sessionBase || "/auth/firebase";
          var requireVerified =
            input.requireVerified === undefined
              ? !!fw._defaults.requireVerified
              : !!input.requireVerified;

          var base = baseState("verify", providerId, returnTo, sessionBase);

          if (typeof input.getAuth !== "function") {
            publishError(
              chain,
              base,
              "verify_not_configured",
              "verify_not_configured",
              "Missing getAuth callback. Call fireauth.verify({ getAuth }, callback)."
            );
            return chain;
          }

          publishLoading(
            chain,
            base,
            "verify_resolving",
            "Finishing sign-in...",
            { requireVerified: requireVerified }
          );

          Promise.resolve()
            .then(function () {
              return resolveCurrentUser(input, {
                providerId: providerId,
                returnTo: returnTo,
                sessionBase: sessionBase,
                requireVerified: requireVerified
              });
            })
            .then(async function (currentUser) {
              if (!currentUser) {
                publishError(chain, base, "verify_missing_token", "missing_token", "No idToken available for verify.");
                return;
              };

              console.log(currentUser);
              console.log(await currentUser.getIdToken())
              var idToken = await currentUser.getIdToken();
              var emailVerified = currentUser.emailVerified;

              if (!idToken) {
                publishError(chain, base, "verify_missing_token", "missing_token", "No idToken available for verify.");
                return;
              }

              if (!isJwt(idToken)) {
                publishError(chain, base, "verify_invalid_token", "invalid_token", "Invalid idToken format.");
                return;
              }

              if (requireVerified && emailVerified === false) {
                console.log("providerData", currentUser.providerData);
                console.log("filtered", currentUser.providerData.filter((z) => z.providerId !== "password" && z.providerid !== "email"))

                // check if provider without password / email is present
                // in that case we allow unverified email
                if (currentUser.providerData.filter((z) => z.providerId !== "password" && z.providerid !== "email").length === 0) {
                  publishError(
                    chain,
                    base,
                    "verify_not_verified",
                    "email_not_verified",
                    "Email not verified yet. Please open the verification link from your email."
                  );
                  return;
                }
              }

              publishLoading(chain, base, "verify_exchange", "Creating session...");

              return exchangeIdTokenForCookie(sessionBase, idToken)
                .then(function () {
                  clearFlowMarkers();
                  publishSuccess(chain, base, "verify_success");
                  window.location.replace(returnTo);
                });
            })
            .catch(function (err) {
              log("error", "verify failed", err);
              publishError(
                chain,
                base,
                "verify_failed",
                "verify_failed",
                "Failed to finish login: " + String((err && err.message) || err)
              );
            });

          return chain;
        };
      })();
    </script>
    """

    Phoenix.HTML.raw(html)
  end

  defp h(nil), do: ""

  defp h(value) when is_binary(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end
end
