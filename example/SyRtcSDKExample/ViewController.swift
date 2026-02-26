import UIKit
import AVFoundation
import SyRtcSDK

class ViewController: UIViewController {
    private let statusLabel = UILabel()
    private let initButton = UIButton(type: .system)
    private let joinButton = UIButton(type: .system)
    private let leaveButton = UIButton(type: .system)
    private let enableAudioButton = UIButton(type: .system)
    private let muteButton = UIButton(type: .system)
    private let enableVideoButton = UIButton(type: .system)
    private let startPreviewButton = UIButton(type: .system)
    private let localVideoView = UIView()
    private let remoteVideoView = UIView()
    private let logTextView = UITextView()
    
    private var engine: SyRtcEngine?
    private var isJoined = false
    private var isMuted = false
    private var autoTestMode = true
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupUI()
        setupEngine()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if autoTestMode {
            autoTestMode = false
            appendLog("自动测试模式启动...")
            appendLog("请求麦克风权限...")
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    self?.appendLog("麦克风权限: \(granted ? "已授权" : "被拒绝")")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self?.runAutoTest()
                    }
                }
            }
        }
    }
    
    private func appendLog(_ msg: String) {
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logTextView.text += "[\(ts)] \(msg)\n"
        let bottom = NSRange(location: logTextView.text.count - 1, length: 1)
        logTextView.scrollRangeToVisible(bottom)
    }
    
    private func runAutoTest() {
        appendLog("步骤1: 初始化引擎...")
        initButtonTapped()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.appendLog("步骤2: 加入房间...")
            self.joinButtonTapped()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.appendLog("步骤3: 测试静音...")
                self.muteButtonTapped()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self.appendLog("步骤4: 取消静音...")
                    self.muteButtonTapped()
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.appendLog("步骤5: 测试启用音频...")
                        self.enableAudioButtonTapped()
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            self.appendLog("步骤6: 离开房间...")
                            self.leaveButtonTapped()
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                self.appendLog("步骤7: 重新加入房间...")
                                self.joinButtonTapped()
                                
                                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                                    self.appendLog("=== 全部测试完成 ===")
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func setupUI() {
        // Status label
        statusLabel.text = "状态: 未初始化"
        statusLabel.numberOfLines = 0
        statusLabel.backgroundColor = UIColor.systemGray6
        statusLabel.layer.cornerRadius = 8
        statusLabel.clipsToBounds = true
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)
        
        // Buttons
        initButton.setTitle("初始化", for: .normal)
        initButton.addTarget(self, action: #selector(initButtonTapped), for: .touchUpInside)
        initButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(initButton)
        
        joinButton.setTitle("加入房间", for: .normal)
        joinButton.addTarget(self, action: #selector(joinButtonTapped), for: .touchUpInside)
        joinButton.isEnabled = false
        joinButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(joinButton)
        
        leaveButton.setTitle("离开房间", for: .normal)
        leaveButton.addTarget(self, action: #selector(leaveButtonTapped), for: .touchUpInside)
        leaveButton.isEnabled = false
        leaveButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(leaveButton)
        
        enableAudioButton.setTitle("启用音频", for: .normal)
        enableAudioButton.addTarget(self, action: #selector(enableAudioButtonTapped), for: .touchUpInside)
        enableAudioButton.isEnabled = false
        enableAudioButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(enableAudioButton)
        
        muteButton.setTitle("静音", for: .normal)
        muteButton.addTarget(self, action: #selector(muteButtonTapped), for: .touchUpInside)
        muteButton.isEnabled = false
        muteButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(muteButton)
        
        enableVideoButton.setTitle("启用视频", for: .normal)
        enableVideoButton.addTarget(self, action: #selector(enableVideoButtonTapped), for: .touchUpInside)
        enableVideoButton.isEnabled = false
        enableVideoButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(enableVideoButton)
        
        startPreviewButton.setTitle("开始预览", for: .normal)
        startPreviewButton.addTarget(self, action: #selector(startPreviewButtonTapped), for: .touchUpInside)
        startPreviewButton.isEnabled = false
        startPreviewButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(startPreviewButton)
        
        // Log text view
        logTextView.isEditable = false
        logTextView.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        logTextView.backgroundColor = UIColor.systemGray6
        logTextView.layer.cornerRadius = 8
        logTextView.clipsToBounds = true
        logTextView.text = ""
        logTextView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(logTextView)
        
        // Video views
        localVideoView.backgroundColor = UIColor.black
        localVideoView.layer.cornerRadius = 8
        localVideoView.clipsToBounds = true
        localVideoView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(localVideoView)
        
        remoteVideoView.backgroundColor = UIColor.darkGray
        remoteVideoView.layer.cornerRadius = 8
        remoteVideoView.clipsToBounds = true
        remoteVideoView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(remoteVideoView)
        
        let safeArea = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 8),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            statusLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),
            
            initButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            initButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            
            joinButton.topAnchor.constraint(equalTo: initButton.topAnchor),
            joinButton.leadingAnchor.constraint(equalTo: initButton.trailingAnchor, constant: 8),
            
            leaveButton.topAnchor.constraint(equalTo: initButton.topAnchor),
            leaveButton.leadingAnchor.constraint(equalTo: joinButton.trailingAnchor, constant: 8),
            
            enableAudioButton.topAnchor.constraint(equalTo: initButton.bottomAnchor, constant: 8),
            enableAudioButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            
            muteButton.topAnchor.constraint(equalTo: enableAudioButton.topAnchor),
            muteButton.leadingAnchor.constraint(equalTo: enableAudioButton.trailingAnchor, constant: 8),
            
            enableVideoButton.topAnchor.constraint(equalTo: enableAudioButton.topAnchor),
            enableVideoButton.leadingAnchor.constraint(equalTo: muteButton.trailingAnchor, constant: 8),
            
            startPreviewButton.topAnchor.constraint(equalTo: enableAudioButton.topAnchor),
            startPreviewButton.leadingAnchor.constraint(equalTo: enableVideoButton.trailingAnchor, constant: 8),
            
            logTextView.topAnchor.constraint(equalTo: enableAudioButton.bottomAnchor, constant: 8),
            logTextView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            logTextView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            logTextView.heightAnchor.constraint(equalToConstant: 200),
            
            localVideoView.topAnchor.constraint(equalTo: logTextView.bottomAnchor, constant: 8),
            localVideoView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            localVideoView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            localVideoView.heightAnchor.constraint(equalToConstant: 120),
            
            remoteVideoView.topAnchor.constraint(equalTo: localVideoView.bottomAnchor, constant: 8),
            remoteVideoView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            remoteVideoView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            remoteVideoView.heightAnchor.constraint(equalToConstant: 120),
        ])
    }
    
    private func setupEngine() {
        engine = SyRtcEngine.shared
        engine?.setEventHandler(self)
    }
    
    private let demoAppId = "APP1769003318261114285E3"
    private let demoAppSecret = "524d401de4c34ad1b554f2b35fe74d6f4f8f7e55614146069b527c1f8799b488"
    private let demoApiBase = "https://syrtcapi.shengyuchenyao.cn/demo-api"
    private let demoSignalingUrl = "wss://syrtcapi.shengyuchenyao.cn/ws/signaling"
    
    @objc private func initButtonTapped() {
        appendLog("初始化引擎 appId=\(demoAppId.prefix(10))...")
        engine?.initialize(appId: demoAppId)
        engine?.setSignalingServerUrl(demoSignalingUrl)
        statusLabel.text = "初始化成功"
        joinButton.isEnabled = true
        appendLog("初始化完成, 信令URL=\(demoSignalingUrl)")
    }
    
    @objc private func joinButtonTapped() {
        guard !isJoined else { return }
        
        statusLabel.text = "正在获取Token..."
        joinButton.isEnabled = false
        appendLog("开始获取Token from \(demoApiBase)...")
        
        DispatchQueue.global().async { [weak self] in
            guard let self = self else { return }
            do {
                let token = try self.fetchToken(channelId: "channel_001", uid: "user_ios")
                DispatchQueue.main.async {
                    self.appendLog("Token获取成功: \(token.prefix(20))...")
                    self.appendLog("正在加入房间 channel_001 uid=user_ios...")
                    self.engine?.join(channelId: "channel_001", uid: "user_ios", token: token)
                    self.engine?.enableLocalAudio(true)
                    self.isJoined = true
                    self.statusLabel.text = "已加入房间"
                    self.leaveButton.isEnabled = true
                    self.enableAudioButton.isEnabled = true
                    self.muteButton.isEnabled = true
                    self.enableVideoButton.isEnabled = true
                    self.startPreviewButton.isEnabled = true
                    self.appendLog("加入房间成功! 音频已启用")
                }
            } catch {
                DispatchQueue.main.async {
                    self.appendLog("加入失败: \(error.localizedDescription)")
                    self.statusLabel.text = "加入房间失败: \(error.localizedDescription)"
                    self.joinButton.isEnabled = true
                }
            }
        }
    }
    
    @objc private func leaveButtonTapped() {
        guard isJoined else { return }
        
        engine?.leave()
        isJoined = false
        statusLabel.text = "离开房间成功"
        joinButton.isEnabled = true
        leaveButton.isEnabled = false
        enableAudioButton.isEnabled = false
        muteButton.isEnabled = false
        enableVideoButton.isEnabled = false
        startPreviewButton.isEnabled = false
        appendLog("已离开房间")
    }
    
    @objc private func enableAudioButtonTapped() {
        engine?.enableLocalAudio(true)
        statusLabel.text = "音频已启用"
        appendLog("启用音频完成")
    }
    
    @objc private func muteButtonTapped() {
        isMuted.toggle()
        engine?.muteLocalAudio(isMuted)
        let state = isMuted ? "已静音" : "已取消静音"
        statusLabel.text = state
        appendLog(state)
    }
    
    @objc private func enableVideoButtonTapped() {
        engine?.enableVideo()
        engine?.setVideoEncoderConfiguration(width: 640, height: 480, frameRate: 15, bitrate: 400)
        statusLabel.text = "视频已启用"
        showToast("视频已启用")
    }
    
    @objc private func startPreviewButtonTapped() {
        engine?.setupLocalVideo(viewId: localVideoView.hash)
        engine?.startPreview()
        statusLabel.text = "预览已开始"
        showToast("预览已开始")
    }
    
    private func fetchToken(channelId: String, uid: String) throws -> String {
        let urlStr = "\(demoApiBase)/api/rtc/token?channelId=\(channelId)&uid=\(uid)&expireHours=24"
        guard let url = URL(string: urlStr) else { throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]) }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.addValue(demoAppId, forHTTPHeaderField: "X-App-Id")
        request.addValue(demoAppSecret, forHTTPHeaderField: "X-App-Secret")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var result: String?
        var fetchError: Error?
        let sem = DispatchSemaphore(value: 0)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            defer { sem.signal() }
            if let error = error { fetchError = error; return }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let code = json["code"] as? Int, code == 0,
                  let token = json["data"] as? String else {
                fetchError = NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Token响应格式错误"])
                return
            }
            result = token
        }.resume()
        
        sem.wait()
        if let error = fetchError { throw error }
        guard let token = result else { throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Token为空"]) }
        return token
    }
    
    private func showToast(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        present(alert, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            alert.dismiss(animated: true)
        }
    }
    
    deinit {
        if isJoined {
            engine?.leave()
        }
        engine?.release()
    }
}

extension ViewController: SyRtcEventHandler {
    func onUserJoined(uid: String, elapsed: Int) {
        DispatchQueue.main.async {
            self.appendLog("事件: 用户加入 uid=\(uid) elapsed=\(elapsed)ms")
            self.statusLabel.text = "用户加入: \(uid)"
            self.engine?.setupRemoteVideo(uid: uid, viewId: self.remoteVideoView.hash)
        }
    }
    
    func onUserOffline(uid: String, reason: String) {
        DispatchQueue.main.async {
            self.appendLog("事件: 用户离开 uid=\(uid) reason=\(reason)")
            self.statusLabel.text = "用户离开: \(uid)"
        }
    }
    
    func onVolumeIndication(speakers: [SyVolumeInfo]) {
        DispatchQueue.main.async {
            if let first = speakers.first {
                self.appendLog("音量: uid=\(first.uid) vol=\(first.volume)")
            }
        }
    }
}
