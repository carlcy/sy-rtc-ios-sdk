import UIKit
import SyRtcSDK

class ViewController: UIViewController {
    // Programmatic UI - no IBOutlets
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
    
    private var engine: SyRtcEngine?
    private var isJoined = false
    private var isMuted = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupUI()
        setupEngine()
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
        
        // Layout
        let safeArea = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            statusLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            
            initButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 16),
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
            
            localVideoView.topAnchor.constraint(equalTo: enableAudioButton.bottomAnchor, constant: 24),
            localVideoView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            localVideoView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            localVideoView.heightAnchor.constraint(equalTo: localVideoView.widthAnchor, multiplier: 9/16),
            
            remoteVideoView.topAnchor.constraint(equalTo: localVideoView.bottomAnchor, constant: 16),
            remoteVideoView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            remoteVideoView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            remoteVideoView.heightAnchor.constraint(equalTo: remoteVideoView.widthAnchor, multiplier: 9/16),
        ])
    }
    
    private func setupEngine() {
        engine = SyRtcEngine.shared
        engine?.setEventHandler(self)
    }
    
    @objc private func initButtonTapped() {
        engine?.initialize(appId: "your_app_id")
        statusLabel.text = "初始化成功"
        joinButton.isEnabled = true
        showToast("初始化成功")
    }
    
    @objc private func joinButtonTapped() {
        guard !isJoined else { return }
        
        let token = getTokenFromServer()
        engine?.join(channelId: "channel_001", uid: "user_001", token: token)
        engine?.enableLocalAudio(true)
        
        isJoined = true
        statusLabel.text = "加入房间成功"
        joinButton.isEnabled = false
        leaveButton.isEnabled = true
        enableAudioButton.isEnabled = true
        muteButton.isEnabled = true
        enableVideoButton.isEnabled = true
        startPreviewButton.isEnabled = true
        showToast("加入房间成功")
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
        showToast("离开房间成功")
    }
    
    @objc private func enableAudioButtonTapped() {
        engine?.enableLocalAudio(true)
        statusLabel.text = "音频已启用"
        showToast("音频已启用")
    }
    
    @objc private func muteButtonTapped() {
        isMuted.toggle()
        engine?.muteLocalAudio(isMuted)
        statusLabel.text = isMuted ? "已静音" : "已取消静音"
        showToast(isMuted ? "已静音" : "已取消静音")
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
    
    private func getTokenFromServer() -> String {
        return "your_token_here"
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
            self.statusLabel.text = "用户加入: \(uid) (耗时: \(elapsed)ms)"
            self.showToast("用户加入: \(uid)")
            self.engine?.setupRemoteVideo(uid: uid, viewId: self.remoteVideoView.hash)
        }
    }
    
    func onUserOffline(uid: String, reason: String) {
        DispatchQueue.main.async {
            self.statusLabel.text = "用户离开: \(uid)"
            self.showToast("用户离开: \(uid)")
        }
    }
    
    func onVolumeIndication(speakers: [SyVolumeInfo]) {
        DispatchQueue.main.async {
            if let first = speakers.first {
                self.statusLabel.text = "音量指示: \(first.uid) = \(first.volume)"
            }
        }
    }
}
