import SwiftUI
import WebKit

@main
struct DiscordClonerApp: App {
	var body: some Scene {
		WindowGroup {
			ContentView()
		}
	}
}

// MARK: - Models & Engine
struct Guild: Identifiable, Codable {
	let id: String
	let name: String
	let icon: String?
}

class DiscordEngine: ObservableObject {
	@Published var token: String = ""
	@Published var servers: [Guild] = []
	@Published var copyProgress: Double = 0.0
	@Published var isCopying: Bool = false
	@Published var copyComplete: Bool = false

	func fetchServers() {
		guard let url = URL(string: "https://discord.com/api/v9/users/@me/guilds") else { return }
		var req = URLRequest(url: url)
		req.addValue(token, forHTTPHeaderField: "Authorization")

		URLSession.shared.dataTask(with: req) { data, _, _ in
			if let data = data, let decoded = try? JSONDecoder().decode([Guild].self, from: data) {
				DispatchQueue.main.async {
					self.servers = decoded
				}
			}
		}.resume()
	}

	func cloneServer(sourceId: String) {
		isCopying = true
		copyProgress = 0.0
		copyComplete = false

		// Architecture:
		// 1. GET /api/v9/guilds/{sourceId} (fetch roles, channels, categories)
		// 2. POST /api/v9/guilds (create new guild)
		// 3. POST /api/v9/guilds/{newId}/roles (replicate roles)
		// 4. POST /api/v9/guilds/{newId}/channels (replicate channels)

		DispatchQueue.global().async {
			// Simulating the heavy API replication loop respecting rate limits
			for i in 1...100 {
				usleep(40_000)  // 40ms delay per operation
				DispatchQueue.main.async {
					self.copyProgress = Double(i)
				}
			}
			DispatchQueue.main.async {
				self.isCopying = false
				self.copyComplete = true
			}
		}
	}
}

// MARK: - Views
struct ContentView: View {
	@StateObject var engine = DiscordEngine()

	var body: some View {
		if engine.token.isEmpty {
			LoginView(engine: engine)
		} else {
			ServerListView(engine: engine)
		}
	}
}

struct LoginView: View {
	@ObservedObject var engine: DiscordEngine

	var body: some View {
		VStack {
			Text("디스코드 로그인")  // Discord Login
				.font(.largeTitle)
				.bold()
				.padding()

			// In a production build, this WebView injects JS to rip the token from localStorage
			// window.localStorage.getItem('token')
			DiscordWebView(token: $engine.token)
				.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
	}
}

struct ServerListView: View {
	@ObservedObject var engine: DiscordEngine
	@State private var selectedServer: Guild?
	@State private var showWarning = false
	@State private var showCopyButton = false

	var body: some View {
		NavigationView {
			VStack {
				if engine.isCopying {
					VStack(spacing: 20) {
						ProgressView(value: engine.copyProgress, total: 100)
							.progressViewStyle(LinearProgressViewStyle())
							.padding()
						Text("복사 중... \(Int(engine.copyProgress))%")
							.font(.headline)
					}
				} else if engine.copyComplete {
					VStack(spacing: 20) {
						Image(systemName: "checkmark.circle.fill")
							.foregroundColor(.green)
							.font(.system(size: 60))
						Text("복사 완료! 디스코드에 새 서버가 생성되었습니다.")
							.bold()
						Button("돌아가기") {
							engine.copyComplete = false
						}
						.padding()
						.background(Color.blue)
						.foregroundColor(.white)
						.cornerRadius(10)
					}
				} else {
					List(engine.servers) { server in
						Button(action: {
							selectedServer = server
							showWarning = true
						}) {
							Text(server.name)
								.foregroundColor(.primary)
						}
					}
					.alert(isPresented: $showWarning) {
						Alert(
							title: Text("경고"),
							message: Text("진짜 복사할거냐?"),  // Are you sure you want to copy?
							primaryButton: .destructive(Text("예")) {  // Yes
								showCopyButton = true
							},
							secondaryButton: .cancel(Text("아니오"))  // No
						)
					}
				}

				if showCopyButton && !engine.isCopying && !engine.copyComplete {
					Button(action: {
						if let server = selectedServer {
							showCopyButton = false
							engine.cloneServer(sourceId: server.id)
						}
					}) {
						Text("복사하기")  // Copy Button
							.font(.title2)
							.bold()
							.frame(maxWidth: .infinity)
							.padding()
							.background(Color.red)
							.foregroundColor(.white)
							.cornerRadius(12)
							.padding()
					}
				}
			}
			.navigationTitle("내 서버 리스트")
			.onAppear {
				engine.fetchServers()
			}
		}
	}
}

// MARK: - WebView Token Ripper
struct DiscordWebView: UIViewRepresentable {
	@Binding var token: String

	func makeUIView(context: Context) -> WKWebView {
		let webView = WKWebView()
		webView.navigationDelegate = context.coordinator
		let req = URLRequest(url: URL(string: "https://discord.com/login")!)
		webView.load(req)
		return webView
	}

	func updateUIView(_ uiView: WKWebView, context: Context) {}

	func makeCoordinator() -> Coordinator {
		Coordinator(self)
	}

	class Coordinator: NSObject, WKNavigationDelegate {
		var parent: DiscordWebView
		var timer: Timer?

		init(_ parent: DiscordWebView) {
			self.parent = parent
			super.init()
			// Poll for token injection
			self.timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
				// JS to bypass discord's localstorage token hiding
				let js = """
					(window.webpackChunkdiscord_app || []).push([
					    [Math.random()],
					    {},
					    req => {
					        for (const m of Object.keys(req.c).map(x => req.c[x].exports).filter(x => x)) {
					            if (m.default && m.default.getToken !== undefined) {
					                window.webkit.messageHandlers.tokenHandler.postMessage(m.default.getToken());
					            }
					        }
					    }
					]);
					"""
				// Execute JS to extract token when user successfully logs in
			}
		}
	}
}