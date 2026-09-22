import UIKit
import AVFoundation
import SyRtcSDK

/// Runnable RTC example: config → init → join/leave → mute → local/remote video.
/// Simulator: microphone may work; camera is usually unavailable. Use a real device for video.
class ViewController: UIViewController, UITextFieldDelegate {
    private let scrollView = UIScrollView()
    private let content = UIStackView()

    private let simBanner = UILabel()
    private let statusLabel = UILabel()

    private let appIdField = UITextField()
    private let appSecretField = UITextField()
    private let apiBaseField = UITextField()
    private let signalingField = UITextField()
    private let channelField = UITextField()
    private let uidField = UITextField()

    private let initButton = UIButton(type: .system)
    private let joinButton = UIButton(type: .system)
    private let leaveButton = UIButton(type: .system)
    private let muteButton = UIButton(type: .system)
    private let enableVideoButton = UIButton(type: .system)
    private let previewButton = UIButton(type: .system)
    private let permButton = UIButton(type: .system)

    private let localTitle = UILabel()
    private let remoteTitle = UILabel()
    private let localVideoView = UIView()
    private let remoteVideoView = UIView()
    private let logTextView = UITextView()

    private var engine: SyRtcEngine?
    private var isJoined = false
    private var isMuted = false
    private var isInitialized = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupUI()
        setupEngine()
        applySimulatorBanner()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        requestPermissions(showAlerts: false)
    }

    // MARK: - Engine

    private func setupEngine() {
        engine = SyRtcEngine.shared
        engine?.setEventHandler(self)
    }

    // MARK: - Permissions

    @objc private func requestPermissionsTapped() {
        requestPermissions(showAlerts: true)
    }

    private func requestPermissions(showAlerts: Bool) {
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                self?.appendLog("麦克风权限: \(granted ? "已授权" : "被拒绝")")
            }
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            appendLog("摄像头权限: 已授权")
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.appendLog("摄像头权限: \(granted ? "已授权" : "被拒绝")")
                }
            }
        case .denied, .restricted:
            appendLog("摄像头权限: 被拒绝（设置 → 隐私）")
            if showAlerts {
                let alert = UIAlertController(
                    title: "需要摄像头权限",
                    message: "真机视频预览需要允许摄像头。模拟器通常没有摄像头。",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "好", style: .default))
                present(alert, animated: true)
            }
        @unknown default:
            break
        }
    }

    // MARK: - Actions

    @objc private func initButtonTapped() {
        let appId = text(appIdField)
        let signaling = text(signalingField)
        let apiBase = text(apiBaseField)
        guard !appId.isEmpty else {
            statusLabel.text = "请填写 AppId"
            return
        }
        appendLog("初始化引擎 appId=\(appId.prefix(12))...")
        engine?.initialize(appId: appId)
        if !signaling.isEmpty {
            engine?.setSignalingServerUrl(signaling)
        }
        if !apiBase.isEmpty {
            engine?.setApiBaseUrl(apiBase)
        }
        isInitialized = true
        joinButton.isEnabled = true
        enableVideoButton.isEnabled = true
        previewButton.isEnabled = true
        statusLabel.text = "状态: 已初始化"
        appendLog("初始化完成 signaling=\(signaling)")
    }

    @objc private func joinButtonTapped() {
        guard !isJoined else { return }
        guard isInitialized else {
            appendLog("请先初始化")
            return
        }
        let channel = text(channelField)
        let uid = text(uidField)
        guard !channel.isEmpty, !uid.isEmpty else {
            statusLabel.text = "请填写频道和用户 ID"
            return
        }
        joinButton.isEnabled = false
        statusLabel.text = "状态: 正在获取 Token..."
        appendLog("获取 Token channel=\(channel) uid=\(uid)")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let token = try self.fetchToken(channelId: channel, uid: uid)
                DispatchQueue.main.async {
                    self.appendLog("Token 获取成功 (\(token.prefix(16))...)")
                    self.engine?.join(channelId: channel, uid: uid, token: token)
                    self.engine?.enableLocalAudio(true)
                    self.isJoined = true
                    self.leaveButton.isEnabled = true
                    self.muteButton.isEnabled = true
                    self.statusLabel.text = "状态: 已加入 \(channel)"
                    self.appendLog("已调用 join + enableLocalAudio")
                }
            } catch {
                DispatchQueue.main.async {
                    self.appendLog("加入失败: \(error.localizedDescription)")
                    self.statusLabel.text = "状态: 加入失败"
                    self.joinButton.isEnabled = true
                }
            }
        }
    }

    @objc private func leaveButtonTapped() {
        guard isJoined else { return }
        engine?.leave()
        isJoined = false
        isMuted = false
        muteButton.setTitle("静音", for: .normal)
        joinButton.isEnabled = true
        leaveButton.isEnabled = false
        muteButton.isEnabled = false
        statusLabel.text = "状态: 已离开"
        appendLog("已离开房间")
    }

    @objc private func muteButtonTapped() {
        isMuted.toggle()
        engine?.muteLocalAudio(isMuted)
        let title = isMuted ? "取消静音" : "静音"
        muteButton.setTitle(title, for: .normal)
        appendLog(isMuted ? "已静音" : "已取消静音")
        statusLabel.text = "状态: \(isMuted ? "已静音" : "麦克风开启")"
    }

    @objc private func enableVideoButtonTapped() {
        engine?.enableVideo()
        engine?.enableLocalVideo(true)
        engine?.setVideoEncoderConfiguration(width: 640, height: 480, frameRate: 15, bitrate: 400)
        engine?.setupLocalVideo(view: localVideoView)
        statusLabel.text = "状态: 视频已启用"
        appendLog("enableVideo + setupLocalVideo(view:)")
        if Self.isSimulator {
            appendLog("模拟器通常无摄像头，本地画面可能是黑的。请用真机验证预览。")
        }
    }

    @objc private func previewButtonTapped() {
        engine?.setupLocalVideo(view: localVideoView)
        engine?.startPreview()
        statusLabel.text = "状态: 已开始预览"
        appendLog("startPreview")
    }

    // MARK: - Token

    private func fetchToken(channelId: String, uid: String) throws -> String {
        let apiBase = text(apiBaseField).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let appId = text(appIdField)
        let appSecret = text(appSecretField)
        let urlStr = "\(apiBase)/api/rtc/token?channelId=\(channelId)&uid=\(uid)&expireHours=24"
        guard let url = URL(string: urlStr) else {
            throw NSError(domain: "SyRtcExample", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.addValue(appId, forHTTPHeaderField: "X-App-Id")
        if !appSecret.isEmpty {
            request.addValue(appSecret, forHTTPHeaderField: "X-App-Secret")
        }
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        var result: String?
        var fetchError: Error?
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, _, error in
            defer { sem.signal() }
            if let error = error { fetchError = error; return }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let code = json["code"] as? Int, code == 0,
                  let token = json["data"] as? String else {
                fetchError = NSError(domain: "SyRtcExample", code: -2, userInfo: [NSLocalizedDescriptionKey: "Token 响应格式错误"])
                return
            }
            result = token
        }.resume()
        sem.wait()
        if let error = fetchError { throw error }
        guard let token = result else {
            throw NSError(domain: "SyRtcExample", code: -3, userInfo: [NSLocalizedDescriptionKey: "Token 为空"])
        }
        return token
    }

    // MARK: - UI

    private static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    private func applySimulatorBanner() {
        if Self.isSimulator {
            simBanner.isHidden = false
            simBanner.text = "模拟器：麦克风可能可用；摄像头通常不可用。请用真机验证本地/远端视频。"
        } else {
            simBanner.isHidden = true
        }
    }

    private func setupUI() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .onDrag
        view.addSubview(scrollView)

        content.axis = .vertical
        content.spacing = 8
        content.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(content)

        simBanner.numberOfLines = 0
        simBanner.font = .systemFont(ofSize: 12)
        simBanner.textColor = .systemOrange
        simBanner.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.12)
        simBanner.layer.cornerRadius = 8
        simBanner.clipsToBounds = true

        statusLabel.text = "状态: 未初始化"
        statusLabel.numberOfLines = 0
        statusLabel.font = .preferredFont(forTextStyle: .headline)

        configure(appIdField, placeholder: "AppId", text: "your_app_id")
        configure(appSecretField, placeholder: "AppSecret", text: "", secure: true)
        // Single switch: "ip-https" | "ip-http" | "domain" | "local"
        let endpointProfile = "ip-https"
        let (apiDefault, sigDefault): (String, String) = {
            switch endpointProfile {
            case "ip-http":
                return ("http://47.105.48.196", "ws://47.105.48.196/ws/signaling")
            case "domain":
                return ("https://syrtcapi.shengyuchenyao.cn", "wss://syrtcapi.shengyuchenyao.cn/ws/signaling")
            case "local":
                return ("http://127.0.0.1:8080", "ws://127.0.0.1:8080/ws/signaling")
            default:
                return ("https://47.105.48.196", "wss://47.105.48.196/ws/signaling")
            }
        }()
        configure(apiBaseField, placeholder: "API Base", text: apiDefault)
        configure(signalingField, placeholder: "Signaling WS", text: sigDefault)
        configure(channelField, placeholder: "Channel ID", text: "channel_001")
        configure(uidField, placeholder: "User ID", text: "user_ios")

        style(initButton, title: "初始化", action: #selector(initButtonTapped))
        style(joinButton, title: "加入房间", action: #selector(joinButtonTapped))
        style(leaveButton, title: "离开房间", action: #selector(leaveButtonTapped))
        style(muteButton, title: "静音", action: #selector(muteButtonTapped))
        style(enableVideoButton, title: "启用视频", action: #selector(enableVideoButtonTapped))
        style(previewButton, title: "开始预览", action: #selector(previewButtonTapped))
        style(permButton, title: "请求权限", action: #selector(requestPermissionsTapped))

        joinButton.isEnabled = false
        leaveButton.isEnabled = false
        muteButton.isEnabled = false
        enableVideoButton.isEnabled = false
        previewButton.isEnabled = false

        localTitle.text = "本地视频"
        localTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        remoteTitle.text = "远端视频"
        remoteTitle.font = .systemFont(ofSize: 13, weight: .semibold)

        localVideoView.backgroundColor = .black
        localVideoView.layer.cornerRadius = 8
        localVideoView.clipsToBounds = true
        remoteVideoView.backgroundColor = .darkGray
        remoteVideoView.layer.cornerRadius = 8
        remoteVideoView.clipsToBounds = true

        logTextView.isEditable = false
        logTextView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        logTextView.backgroundColor = .systemGray6
        logTextView.layer.cornerRadius = 8
        logTextView.clipsToBounds = true

        let row1 = buttonRow([initButton, joinButton, leaveButton])
        let row2 = buttonRow([muteButton, enableVideoButton, previewButton])
        let row3 = buttonRow([permButton])

        [simBanner, statusLabel,
         labeled("AppId", appIdField),
         labeled("AppSecret", appSecretField),
         labeled("API Base", apiBaseField),
         labeled("Signaling", signalingField),
         labeled("Channel", channelField),
         labeled("UID", uidField),
         row1, row2, row3,
         localTitle, localVideoView,
         remoteTitle, remoteVideoView,
         logTextView].forEach { content.addArrangedSubview($0) }

        localVideoView.heightAnchor.constraint(equalToConstant: 160).isActive = true
        remoteVideoView.heightAnchor.constraint(equalToConstant: 160).isActive = true
        logTextView.heightAnchor.constraint(equalToConstant: 180).isActive = true

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 12),
            content.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
        ])
    }

    private func configure(_ field: UITextField, placeholder: String, text: String, secure: Bool = false) {
        field.placeholder = placeholder
        field.text = text
        field.borderStyle = .roundedRect
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.isSecureTextEntry = secure
        field.delegate = self
        field.font = .systemFont(ofSize: 14)
        field.returnKeyType = .done
    }

    private func style(_ button: UIButton, title: String, action: Selector) {
        button.setTitle(title, for: .normal)
        button.addTarget(self, action: action, for: .touchUpInside)
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
    }

    private func labeled(_ title: String, _ field: UITextField) -> UIStackView {
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        let stack = UIStackView(arrangedSubviews: [label, field])
        stack.axis = .vertical
        stack.spacing = 2
        return stack
    }

    private func buttonRow(_ buttons: [UIButton]) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: buttons)
        stack.axis = .horizontal
        stack.spacing = 8
        stack.distribution = .fillEqually
        return stack
    }

    private func text(_ field: UITextField) -> String {
        (field.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func appendLog(_ msg: String) {
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logTextView.text += "[\(ts)] \(msg)\n"
        if logTextView.text.count > 1 {
            let bottom = NSRange(location: logTextView.text.count - 1, length: 1)
            logTextView.scrollRangeToVisible(bottom)
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    deinit {
        if isJoined { engine?.leave() }
        engine?.release()
    }
}

extension ViewController: SyRtcEventHandler {
    func onJoinChannelSuccess(channelId: String, uid: String, elapsed: Int) {
        DispatchQueue.main.async {
            self.appendLog("加入频道成功: \(channelId) uid=\(uid) (\(elapsed)ms)")
            self.statusLabel.text = "状态: 已加入 \(channelId)"
        }
    }

    func onLeaveChannel(stats: [String: Any]) {
        DispatchQueue.main.async {
            self.appendLog("已离开频道")
            self.statusLabel.text = "状态: 已离开"
        }
    }

    func onRejoinChannelSuccess(channelId: String, uid: String, elapsed: Int) {
        DispatchQueue.main.async {
            self.appendLog("重连成功 \(channelId)")
        }
    }

    func onConnectionStateChanged(state: String, reason: String) {
        DispatchQueue.main.async {
            self.appendLog("连接: state=\(state) reason=\(reason)")
        }
    }

    func onNetworkQuality(uid: String, txQuality: String, rxQuality: String) {
        let poor = txQuality.lowercased().contains("poor") || rxQuality.lowercased().contains("poor")
        guard poor else { return }
        DispatchQueue.main.async {
            self.appendLog("网络较差 uid=\(uid) tx=\(txQuality) rx=\(rxQuality)")
        }
    }

    func onUserMuteAudio(uid: String, muted: Bool) {
        DispatchQueue.main.async {
            self.appendLog("远端静音 uid=\(uid) muted=\(muted)")
        }
    }

    func onLocalAudioStateChanged(state: String, error: String) {
        DispatchQueue.main.async {
            self.appendLog("本地音频 state=\(state) error=\(error)")
        }
    }

    func onRemoteAudioStateChanged(uid: String, state: String, reason: String, elapsed: Int) {
        DispatchQueue.main.async {
            self.appendLog("远端音频 uid=\(uid) state=\(state)")
        }
    }

    func onAudioRoutingChanged(routing: Int) {
        DispatchQueue.main.async {
            self.appendLog("音频路由=\(routing)")
        }
    }

    func onTokenPrivilegeWillExpire() {
        DispatchQueue.main.async {
            self.appendLog("Token 即将过期，请重新加入")
        }
    }

    func onError(code: Int, message: String) {
        DispatchQueue.main.async {
            self.appendLog("错误 code=\(code) \(message)")
            self.statusLabel.text = "状态: 错误 \(message)"
        }
    }

    func onUserJoined(uid: String, elapsed: Int) {
        DispatchQueue.main.async {
            self.appendLog("用户加入 uid=\(uid)")
            self.engine?.setupRemoteVideo(uid: uid, view: self.remoteVideoView)
        }
    }

    func onUserOffline(uid: String, reason: String) {
        DispatchQueue.main.async {
            self.appendLog("用户离开 uid=\(uid) reason=\(reason)")
        }
    }

    func onVolumeIndication(speakers: [SyVolumeInfo]) {
        // noisy; skip logging every tick
    }
}
