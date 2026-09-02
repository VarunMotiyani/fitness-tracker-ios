import SwiftUI
import WebKit
import FitnessDomain
import Metrics

public enum MuscleMapModeState: Equatable {
    case balance([String: Int], hard: Bool)
    case fatigue([String: Double])
    case strength([String: Double])
}

public struct InteractiveBodyMapView: View {
    public let modeState: MuscleMapModeState
    public let bodyType: String // "male" or "female"
    @Binding public var selectedMuscleSlug: String?
    public var onMuscleTapped: ((String) -> Void)?

    public init(
        modeState: MuscleMapModeState,
        bodyType: String = "male",
        selectedMuscleSlug: Binding<String?>,
        onMuscleTapped: ((String) -> Void)? = nil
    ) {
        self.modeState = modeState
        self.bodyType = bodyType
        self._selectedMuscleSlug = selectedMuscleSlug
        self.onMuscleTapped = onMuscleTapped
    }

    public var body: some View {
        BodyMapWebKitView(
            modeState: modeState,
            bodyType: bodyType,
            selectedMuscleSlug: $selectedMuscleSlug,
            onMuscleTapped: onMuscleTapped
        )
        .frame(height: 310)
        .background(GymTheme.surface2, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct BodyMapWebKitView: UIViewRepresentable {
    let modeState: MuscleMapModeState
    let bodyType: String
    @Binding var selectedMuscleSlug: String?
    let onMuscleTapped: ((String) -> Void)?

    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: BodyMapWebKitView
        var isLoaded = false

        init(_ parent: BodyMapWebKitView) {
            self.parent = parent
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "onMuscle", let slug = message.body as? String {
                DispatchQueue.main.async {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        if self.parent.selectedMuscleSlug == slug {
                            self.parent.selectedMuscleSlug = nil
                        } else {
                            self.parent.selectedMuscleSlug = slug
                        }
                    }
                    self.parent.onMuscleTapped?(slug)
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            parent.applyState(to: webView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "onMuscle")

        let config = WKWebViewConfiguration()
        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.navigationDelegate = context.coordinator

        let html = generateInitialHTML()
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.isLoaded {
            applyState(to: webView)
        }
    }

    func applyState(to webView: WKWebView) {
        let sel = selectedMuscleSlug ?? ""
        let modeJSON = modeDataJSON()
        let js = "if (window.setSelection) window.setSelection('\(sel)'); if (window.setMode) window.setMode(\(modeJSON));"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func modeDataJSON() -> String {
        switch modeState {
        case .balance(let counts, let hard):
            let maxCount = max(1, counts.values.max() ?? 1)
            var levels: [String: Int] = [:]
            for (k, v) in counts {
                let ratio = Double(v) / Double(maxCount)
                if ratio >= 0.75 { levels[k] = 4 }
                else if ratio >= 0.50 { levels[k] = 3 }
                else if ratio >= 0.25 { levels[k] = 2 }
                else if ratio > 0 { levels[k] = 1 }
                else { levels[k] = 0 }
            }
            if let data = try? JSONSerialization.data(withJSONObject: ["type": "balance", "hard": hard, "levels": levels]),
               let str = String(data: data, encoding: .utf8) {
                return str
            }
        case .fatigue(let fatigues):
            var levels: [String: Int] = [:]
            for (k, v) in fatigues {
                if v >= 0.55 { levels[k] = 4 }
                else if v >= 0.40 { levels[k] = 3 }
                else if v >= 0.25 { levels[k] = 2 }
                else if v >= 0.15 { levels[k] = 1 }
                else { levels[k] = 0 }
            }
            if let data = try? JSONSerialization.data(withJSONObject: ["type": "fatigue", "levels": levels]),
               let str = String(data: data, encoding: .utf8) {
                return str
            }
        case .strength(let strengths):
            var levels: [String: Int] = [:]
            for (k, v) in strengths {
                if v >= 1.0 { levels[k] = 4 }
                else if v >= 0.875 { levels[k] = 3 }
                else if v >= 0.75 { levels[k] = 2 }
                else if v >= 0.625 { levels[k] = 1 }
                else { levels[k] = 0 }
            }
            if let data = try? JSONSerialization.data(withJSONObject: ["type": "strength", "levels": levels]),
               let str = String(data: data, encoding: .utf8) {
                return str
            }
        }
        return "{}"
    }

    private func generateInitialHTML() -> String {
        let frontSVG: String
        let backSVG: String

        if bodyType == "female" {
            frontSVG = BodyMapSVGStore.femaleFrontSVG
            backSVG = BodyMapSVGStore.femaleBackSVG
        } else {
            frontSVG = BodyMapSVGStore.maleFrontSVG
            backSVG = BodyMapSVGStore.maleBackSVG
        }

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <style>
          * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; margin: 0; padding: 0; }
          body {
            background: transparent;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            overflow: hidden;
            font-family: -apple-system, BlinkMacSystemFont, sans-serif;
            user-select: none;
            -webkit-user-select: none;
          }
          .bodymap {
            display: flex;
            gap: 16px;
            justify-content: center;
            align-items: center;
            width: 100%;
            height: 100%;
            padding: 10px 14px;
            --bm-base: #28282a;
            --bm-sil: #3a3a3c;
          }
          .bm-v {
            flex: 1;
            height: 100%;
            max-height: 290px;
          }
          .bm-v path {
            stroke: #1c1c1e;
            stroke-width: 3.5;
            stroke-linejoin: round;
          }
          .bm-sil {
            fill: var(--bm-sil);
          }
          .bm-m {
            fill: var(--bm-base);
            cursor: pointer;
            transition: fill 0.25s cubic-bezier(0.4, 0, 0.2, 1);
          }
          /* Muscle Balance Mode */
          .bm-m.l1 { fill: #285434; }
          .bm-m.l2 { fill: #2a8442; }
          .bm-m.l3 { fill: #2cad4e; }
          .bm-m.l4 { fill: #30d158; }

          /* Hard Mode */
          .hard-mode .bm-m.l1 { fill: #5a5426; }
          .hard-mode .bm-m.l2 { fill: #948726; }
          .hard-mode .bm-m.l3 { fill: #c7b31e; }
          .hard-mode .bm-m.l4 { fill: #ffd60a; }

          /* Fatigue Mode */
          .hm-fatigue .bm-m.l0 { fill: #28282a; }
          .hm-fatigue .bm-m.l1 { fill: #5a5426; }
          .hm-fatigue .bm-m.l2 { fill: #ffd60a; }
          .hm-fatigue .bm-m.l3 { fill: #ff9f0a; }
          .hm-fatigue .bm-m.l4 { fill: #ff453a; }

          /* Strength Mode */
          .hm-strength .bm-m.l0 { fill: #28282a; }
          .hm-strength .bm-m.l1 { fill: #285434; }
          .hm-strength .bm-m.l2 { fill: #2a8442; }
          .hm-strength .bm-m.l3 { fill: #2cad4e; }
          .hm-strength .bm-m.l4 { fill: #ffd60a; filter: drop-shadow(0 0 2px #ffd60a); }

          /* Selected Muscle Highlight Outline */
          .bm-m.sel {
            stroke: #ffffff !important;
            stroke-width: 9 !important;
            stroke-linejoin: round;
            paint-order: stroke fill;
            filter: drop-shadow(0 0 6px rgba(255,255,255,0.9));
          }
        </style>
        </head>
        <body>
          <div id="container" class="bodymap">
            \(frontSVG)
            \(backSVG)
          </div>

          <script>
            let currentSel = '';

            function handleMuscle(slug) {
              if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.onMuscle) {
                window.webkit.messageHandlers.onMuscle.postMessage(slug);
              }
            }

            window.setSelection = function(slug) {
              currentSel = slug;
              document.querySelectorAll('.bm-m').forEach(el => {
                if (slug && el.getAttribute('data-slug') === slug) {
                  el.classList.add('sel');
                } else {
                  el.classList.remove('sel');
                }
              });
            };

            window.setMode = function(data) {
              try {
                const container = document.getElementById('container');
                container.className = 'bodymap';

                if (data.type === 'fatigue') {
                  container.classList.add('hm-fatigue');
                } else if (data.type === 'strength') {
                  container.classList.add('hm-strength');
                } else if (data.type === 'balance' && data.hard) {
                  container.classList.add('hard-mode');
                }

                const levels = data.levels || {};
                document.querySelectorAll('.bm-m').forEach(el => {
                  const slug = el.getAttribute('data-slug');
                  const lvl = levels[slug] || 0;
                  el.className = 'bm-m l' + lvl + (slug === currentSel ? ' sel' : '');
                });
              } catch (e) {
                console.error(e);
              }
            };
          </script>
        </body>
        </html>
        """
    }
}
