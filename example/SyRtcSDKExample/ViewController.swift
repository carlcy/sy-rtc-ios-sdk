import UIKit
import SyRtcSDK

class ViewController: UIViewController {
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var initButton: UIButton!
    @IBOutlet weak var joinButton: UIButton!
    @IBOutlet weak var leaveButton: UIButton!
    @IBOutlet weak var enableAudioButton: UIButton!
    @IBOutlet weak var muteButton: UIButton!
    @IBOutlet weak var enableVideoButton: UIButton!
    @IBOutlet weak var startPreviewButton: UIButton!
    @IBOutlet weak var localVideoView: UIView!
    @IBOutlet weak var remoteVideoView: UIView!
    
    private var engine: SyRtcEngine?
    private var isJoined = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupUI()
        setupEngine()
    }
    
    private func setupUI() {
        statusLabel.text = "状态: 未初始化"
        statusLabel.numberOfLines = 0
        statusLabel.backgroundColor = UIColor.systemGray6
        statusLabel.layer.cornerRadius = 8
        statusLabel.clipsToBounds = true
        
        joinButton.isEnabled = false
        leaveButton.isEnabled = false
        enableAudioButton.isEnabled = false
        muteButton.isEnabled = false
        enableVideoButton.isEnabled = false
        startPreviewButton.isEnabled = false
        
        // 设置视频视图
        localVideoView.backgroundColor = UIColor.black
        localVideoView.layer.cornerRadius = 8
        localVideoView.clipsToBounds = true
        
        remoteVideoView.backgroundColor = UIColor.darkGray
        remoteVideoView.layer.cornerRadius = 8
        remoteVideoView.clipsToBounds = true
    }
    
    private func setupEngine() {
        engine = SyRtcEngine.shared
        engine?.setEventHandler(self)
    }
    
    @IBAction func initButtonTapped(_ sender: UIButton) {
        Task {
            do {
                try await engine?.init(appId: "your_app_id")
                await MainActor.run {
                    statusLabel.text = "初始化成功"
                    joinButton.isEnabled = true
                    showToast("初始化成功")
                }
            } catch {
                await MainActor.run {
                    statusLabel.text = "初始化失败: \(error.localizedDescription)"
                    showToast("初始化失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    @IBAction func joinButtonTapped(_ sender: UIButton) {
        guard !isJoined else { return }
        
        Task {
            do {
                // 从服务器获取Token（实际使用时需要实现HTTP请求）
                let token = try await getTokenFromServer()
                
                // 加入房间
                try await engine?.join(
                    channelId: "channel_001",
                    uid: "user_001",
                    token: token
                )
                
                // 启用本地音频
                try await engine?.enableLocalAudio(enabled: true)
                
                await MainActor.run {
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
            } catch {
                await MainActor.run {
                    statusLabel.text = "加入房间失败: \(error.localizedDescription)"
                    showToast("加入房间失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    @IBAction func leaveButtonTapped(_ sender: UIButton) {
        guard isJoined else { return }
        
        Task {
            do {
                try await engine?.leave()
                await MainActor.run {
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
            } catch {
                await MainActor.run {
                    statusLabel.text = "离开房间失败: \(error.localizedDescription)"
                    showToast("离开房间失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    @IBAction func enableAudioButtonTapped(_ sender: UIButton) {
        Task {
            do {
                try await engine?.enableLocalAudio(enabled: true)
                await MainActor.run {
                    statusLabel.text = "音频已启用"
                    showToast("音频已启用")
                }
            } catch {
                await MainActor.run {
                    statusLabel.text = "启用音频失败: \(error.localizedDescription)"
                    showToast("启用音频失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    @IBAction func muteButtonTapped(_ sender: UIButton) {
        Task {
            do {
                let isMuted = await engine?.isLocalAudioMuted() ?? false
                try await engine?.muteLocalAudio(muted: !isMuted)
                await MainActor.run {
                    let newState = !isMuted
                    statusLabel.text = newState ? "已静音" : "已取消静音"
                    showToast(newState ? "已静音" : "已取消静音")
                }
            } catch {
                await MainActor.run {
                    statusLabel.text = "静音操作失败: \(error.localizedDescription)"
                    showToast("静音操作失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    @IBAction func enableVideoButtonTapped(_ sender: UIButton) {
        Task {
            do {
                // 检查是否有直播权限（实际应该从后端查询）
                // 这里简化处理，假设有权限
                try await engine?.enableVideo()
                
                // 设置视频编码配置
                try await engine?.setVideoEncoderConfiguration(
                    width: 640,
                    height: 480,
                    frameRate: 15,
                    bitrate: 400
                )
                
                await MainActor.run {
                    statusLabel.text = "视频已启用"
                    showToast("视频已启用")
                }
            } catch {
                await MainActor.run {
                    statusLabel.text = "启用视频失败: \(error.localizedDescription)"
                    showToast("启用视频失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    @IBAction func startPreviewButtonTapped(_ sender: UIButton) {
        // 设置本地视频视图（使用viewId）
        engine?.setupLocalVideo(viewId: localVideoView.hash)
        
        // 开始预览
        engine?.startPreview()
        
        statusLabel.text = "预览已开始"
        showToast("预览已开始")
    }
    
    private func getTokenFromServer() async throws -> String {
        // 实际实现应该调用您的后端API获取Token
        // 示例：
        // let url = URL(string: "https://your-api.com/api/rtc/token?channelId=channel_001&uid=user_001")!
        // let (data, _) = try await URLSession.shared.data(from: url)
        // let response = try JSONDecoder().decode(TokenResponse.self, from: data)
        // return response.token
        
        // 这里返回示例Token，实际使用时请替换为真实的Token获取逻辑
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
            Task {
                try? await engine?.leave()
            }
        }
        engine?.release()
    }
}

extension ViewController: SyRtcEventHandler {
    func onUserJoined(uid: String, elapsed: Int) {
        DispatchQueue.main.async {
            self.statusLabel.text = "用户加入: \(uid) (耗时: \(elapsed)ms)"
            self.showToast("用户加入: \(uid)")
            
            // 设置远端视频视图（使用viewId）
            self.engine?.setupRemoteVideo(uid: uid, viewId: self.remoteVideoView.hash)
        }
    }
    
    func onUserOffline(uid: String, reason: Int) {
        DispatchQueue.main.async {
            self.statusLabel.text = "用户离开: \(uid)"
            self.showToast("用户离开: \(uid)")
        }
    }
    
    func onVolumeIndication(speakers: [VolumeInfo]) {
        DispatchQueue.main.async {
            if let first = speakers.first {
                self.statusLabel.text = "音量指示: \(first.uid) = \(first.volume)"
            }
        }
    }
}
