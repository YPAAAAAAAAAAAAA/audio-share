#!/usr/bin/env python3
"""
Step Realtime API 智能音频分类测试
测试环境音 vs 人声检测 + 5-10秒实时总结
"""

import asyncio
import websockets
import json
import base64
import numpy as np
import time

API_KEY = "8FyDGELcpTdfh1JNOoePkfXzCtExQHL8DSdEX9UYfl4dCsE77R4WIUOIJqanw0Cl"
WS_URL = "wss://api.stepfun.com/v1/realtime"

class IntelligentAudioTester:
    def __init__(self):
        self.websocket = None
        self.test_results = []
        self.current_test = None
        
    async def connect(self):
        """连接到Step Realtime API"""
        try:
            self.websocket = await websockets.connect(
                f"{WS_URL}?model=step-audio-2-mini",
                additional_headers={
                    "Authorization": f"Bearer {API_KEY}"
                }
            )
            print("✅ 成功连接到Step Realtime API")
            return True
        except Exception as e:
            print(f"❌ 连接失败: {e}")
            return False
    
    async def send_session_config(self, test_scenario):
        """根据测试场景发送不同的session配置"""
        
        if test_scenario == "environment_sound":
            instructions = """你是一个专业的环境音分析助手。
            当检测到环境声音时，请：
            1. 识别声音类型（自然/机械/音乐等）
            2. 用3-6个字描述环境特征
            3. 如果听到人声，请标注"检测到人声"
            专注于环境音分析，响应要简洁精准。"""
            
            voice = "qingchunshaonv"
            silence_duration = 300  # 更短的静音检测
            threshold = 0.3  # 更低的阈值检测环境音
            
        else:  # human_voice
            instructions = """你是一个专业的语音总结助手。
            当用户说话时，请：
            1. 准确转录中文语音
            2. 用5-8个字总结核心内容
            3. 识别语音情绪和紧急程度
            4. 如果是环境音，请标注"非人声音频"
            专注于人声理解，保持简洁精准。"""
            
            voice = "qingchunshaonv"
            silence_duration = 600  # 标准静音检测
            threshold = 0.5  # 标准阈值
        
        config = {
            "event_id": f"session_config_{test_scenario}",
            "type": "session.update",
            "session": {
                "modalities": ["text", "audio"],
                "instructions": instructions,
                "voice": voice,
                "input_audio_format": "pcm16",
                "output_audio_format": "pcm16",
                "turn_detection": {
                    "type": "server_vad",
                    "threshold": threshold,
                    "silence_duration_ms": silence_duration
                }
            }
        }
        
        await self.websocket.send(json.dumps(config))
        print(f"📤 发送{test_scenario}专用配置")
    
    async def generate_environment_audio(self, sound_type):
        """生成不同类型的环境音"""
        sample_rate = 16000
        duration = 3.0  # 3秒音频
        
        if sound_type == "nature":
            # 生成风声和鸟叫声的组合
            t = np.linspace(0, duration, int(sample_rate * duration), False)
            # 风声 (低频噪音)
            wind = np.random.normal(0, 0.1, len(t)) * np.sin(2 * np.pi * 0.5 * t)
            # 鸟叫声 (高频短脉冲)
            bird_chirps = np.zeros(len(t))
            for i in range(5):  # 5声鸟叫
                start_idx = int(np.random.uniform(0.2, 2.5) * sample_rate)
                end_idx = start_idx + int(0.3 * sample_rate)
                if end_idx < len(t):
                    freq = np.random.uniform(800, 1200)
                    bird_chirps[start_idx:end_idx] = np.sin(2 * np.pi * freq * t[start_idx:end_idx]) * 0.3
            
            audio_data = (wind + bird_chirps) * 0.4
            
        elif sound_type == "mechanical":
            # 生成机械运转声
            t = np.linspace(0, duration, int(sample_rate * duration), False)
            # 电机转动声 (稳定频率)
            motor = np.sin(2 * np.pi * 60 * t) * 0.2  # 60Hz
            # 齿轮声 (周期性咔哒声)
            gear_noise = np.random.normal(0, 0.1, len(t))
            audio_data = (motor + gear_noise) * 0.5
            
        elif sound_type == "music":
            # 生成简单的音乐旋律
            t = np.linspace(0, duration, int(sample_rate * duration), False)
            notes = [440, 494, 523, 587]  # A, B, C, D
            melody = np.zeros(len(t))
            note_duration = duration / len(notes)
            
            for i, freq in enumerate(notes):
                start_idx = int(i * note_duration * sample_rate)
                end_idx = int((i + 1) * note_duration * sample_rate)
                if end_idx <= len(t):
                    melody[start_idx:end_idx] = np.sin(2 * np.pi * freq * t[start_idx:end_idx])
            
            audio_data = melody * 0.3
            
        else:  # human_speech simulation
            # 生成模拟人声的复杂波形
            t = np.linspace(0, duration, int(sample_rate * duration), False)
            # 基频 + 谐波结构模拟人声
            fundamental = 150  # 基频
            voice = (np.sin(2 * np.pi * fundamental * t) * 0.4 +
                    np.sin(2 * np.pi * fundamental * 2 * t) * 0.2 +
                    np.sin(2 * np.pi * fundamental * 3 * t) * 0.1)
            
            # 添加语音的包络变化
            envelope = np.abs(np.sin(2 * np.pi * 3 * t))  # 3Hz的包络变化
            audio_data = voice * envelope * 0.3
        
        # 转换为16位PCM
        audio_int16 = np.clip(audio_data * 32767, -32767, 32767).astype(np.int16)
        audio_bytes = audio_int16.tobytes()
        
        return base64.b64encode(audio_bytes).decode()
    
    async def send_test_audio(self, audio_data, test_name):
        """发送测试音频并记录时间"""
        start_time = time.time()
        
        # 分块发送音频 (模拟实时流)
        chunk_size = 3200  # 200ms的音频数据
        for i in range(0, len(audio_data), chunk_size):
            chunk = audio_data[i:i+chunk_size]
            
            message = {
                "event_id": f"audio_chunk_{test_name}_{i//chunk_size}",
                "type": "input_audio_buffer.append",
                "audio": chunk
            }
            
            await self.websocket.send(json.dumps(message))
            await asyncio.sleep(0.2)  # 模拟实时发送
        
        print(f"📤 发送{test_name}音频数据")
        
        # 提交音频缓冲区
        commit_message = {
            "event_id": f"commit_{test_name}",
            "type": "input_audio_buffer.commit"
        }
        await self.websocket.send(json.dumps(commit_message))
        
        return start_time
    
    async def run_classification_test(self, test_scenario, sound_type):
        """运行单个分类测试"""
        print(f"\n🔬 开始测试: {test_scenario} - {sound_type}")
        
        self.current_test = {
            "scenario": test_scenario,
            "sound_type": sound_type,
            "start_time": time.time(),
            "responses": []
        }
        
        # 配置session
        await self.send_session_config(test_scenario)
        await asyncio.sleep(1)
        
        # 生成和发送测试音频
        if sound_type in ["nature", "mechanical", "music"]:
            audio_data = await self.generate_environment_audio(sound_type)
        else:  # human_speech
            audio_data = await self.generate_environment_audio("human_speech")
        
        send_start = await self.send_test_audio(audio_data, f"{test_scenario}_{sound_type}")
        
        # 等待响应 (最多10秒)
        response_timeout = 10
        await asyncio.sleep(response_timeout)
        
        # 分析结果
        await self.analyze_test_result()
        
    async def analyze_test_result(self):
        """分析测试结果"""
        if not self.current_test:
            return
        
        test = self.current_test
        total_time = time.time() - test["start_time"]
        
        print(f"\n📊 测试结果分析:")
        print(f"   场景: {test['scenario']}")
        print(f"   音频类型: {test['sound_type']}")
        print(f"   总用时: {total_time:.2f}秒")
        print(f"   响应数量: {len(test['responses'])}")
        
        # 检查响应质量
        has_transcription = any("transcript" in r for r in test["responses"])
        has_summary = any("content" in r and len(r.get("content", "")) >= 3 for r in test["responses"])
        response_time = min([r.get("time", 999) for r in test["responses"]] + [999])
        
        print(f"   ✅ 转录检测: {'是' if has_transcription else '否'}")
        print(f"   ✅ 智能总结: {'是' if has_summary else '否'}")
        print(f"   ⏱️ 首次响应: {response_time:.2f}秒")
        
        # 评估准确性
        accuracy_score = self.evaluate_accuracy(test)
        print(f"   🎯 准确度评分: {accuracy_score}/5")
        
        self.test_results.append(test)
        self.current_test = None
    
    def evaluate_accuracy(self, test):
        """评估分类准确性"""
        scenario = test["scenario"]
        sound_type = test["sound_type"]
        responses = test["responses"]
        
        score = 0
        
        # 基础分 - 有响应
        if responses:
            score += 1
        
        # 时效分 - 10秒内响应
        fast_response = any(r.get("time", 999) <= 10 for r in responses)
        if fast_response:
            score += 1
        
        # 内容分 - 响应相关性
        relevant_content = False
        for r in responses:
            content = r.get("content", "").lower()
            if scenario == "environment_sound":
                if sound_type == "nature" and ("自然" in content or "风" in content or "鸟" in content):
                    relevant_content = True
                elif sound_type == "mechanical" and ("机械" in content or "电机" in content or "运转" in content):
                    relevant_content = True
                elif sound_type == "music" and ("音乐" in content or "旋律" in content or "乐音" in content):
                    relevant_content = True
            elif scenario == "human_voice":
                if sound_type == "human_speech" and ("语音" in content or "说话" in content or "人声" in content):
                    relevant_content = True
        
        if relevant_content:
            score += 2
        
        # 长度分 - 3-8字总结
        appropriate_length = any(3 <= len(r.get("content", "")) <= 10 for r in responses)
        if appropriate_length:
            score += 1
        
        return score
    
    async def listen_for_responses(self):
        """监听服务器响应并记录测试数据"""
        async for message in self.websocket:
            try:
                data = json.loads(message)
                event_type = data.get("type", "unknown")
                
                # 记录响应时间
                if self.current_test:
                    response_data = {
                        "type": event_type,
                        "time": time.time() - self.current_test["start_time"],
                        "data": data
                    }
                
                if event_type == "session.created":
                    print("✅ Session创建成功")
                    
                elif event_type == "session.updated":
                    print("✅ Session配置更新成功")
                    
                elif event_type == "conversation.item.input_audio_transcription.completed":
                    transcript = data.get("transcript", "")
                    print(f"🎤 转录完成: {transcript}")
                    
                    if self.current_test:
                        response_data["transcript"] = transcript
                        self.current_test["responses"].append(response_data)
                    
                elif event_type == "response.text.done":
                    content = data.get("content", "")
                    print(f"💡 AI分析结果: {content}")
                    
                    if self.current_test:
                        response_data["content"] = content
                        self.current_test["responses"].append(response_data)
                    
                elif event_type == "response.audio_transcript.done":
                    transcript = data.get("transcript", "")
                    print(f"🤖 AI回复转录: {transcript}")
                    
                    if self.current_test:
                        response_data["ai_transcript"] = transcript
                        self.current_test["responses"].append(response_data)
                    
                elif event_type == "error":
                    error_info = data.get("error", {})
                    print(f"❌ 错误: {error_info.get('message', 'Unknown error')}")
                    
                    if self.current_test:
                        response_data["error"] = error_info
                        self.current_test["responses"].append(response_data)
                    
            except Exception as e:
                print(f"❌ 解析消息失败: {e}")

async def main():
    """主测试函数 - 全面测试智能音频分类"""
    tester = IntelligentAudioTester()
    
    print("🧪 开始智能音频分类全面测试")
    print(f"📡 API密钥: {API_KEY[:20]}...")
    print("=" * 60)
    
    # 连接测试
    if not await tester.connect():
        print("❌ 连接失败，测试终止")
        return
    
    # 启动响应监听
    listen_task = asyncio.create_task(tester.listen_for_responses())
    
    try:
        # 测试场景定义
        test_scenarios = [
            ("environment_sound", "nature"),      # 环境音检测 - 自然音
            ("environment_sound", "mechanical"),  # 环境音检测 - 机械音
            ("environment_sound", "music"),       # 环境音检测 - 音乐
            ("human_voice", "human_speech"),      # 人声检测 - 人声
            ("human_voice", "nature"),            # 人声检测 - 自然音(误判测试)
            ("environment_sound", "human_speech") # 环境音检测 - 人声(误判测试)
        ]
        
        print("🎯 测试计划:")
        for i, (scenario, sound_type) in enumerate(test_scenarios, 1):
            print(f"   {i}. {scenario} → {sound_type}")
        print()
        
        # 执行所有测试
        for i, (scenario, sound_type) in enumerate(test_scenarios, 1):
            print(f"\n{'='*20} 测试 {i}/{len(test_scenarios)} {'='*20}")
            await tester.run_classification_test(scenario, sound_type)
            
            if i < len(test_scenarios):
                print("⏸️ 等待3秒后进行下一测试...")
                await asyncio.sleep(3)
        
        # 生成最终报告
        print(f"\n{'='*60}")
        print("📋 测试总结报告")
        print(f"{'='*60}")
        
        total_tests = len(tester.test_results)
        total_score = sum(tester.evaluate_accuracy(test) for test in tester.test_results)
        max_score = total_tests * 5
        
        print(f"总测试数量: {total_tests}")
        print(f"总得分: {total_score}/{max_score} ({total_score/max_score*100:.1f}%)")
        print()
        
        # 详细结果
        for i, test in enumerate(tester.test_results, 1):
            score = tester.evaluate_accuracy(test)
            status = "✅ 优秀" if score >= 4 else "⚠️ 良好" if score >= 3 else "❌ 需优化"
            
            print(f"{i}. {test['scenario']} → {test['sound_type']}: {score}/5 {status}")
            
            # 显示响应内容
            for response in test["responses"]:
                if "content" in response:
                    print(f"   💬 AI回复: {response['content']}")
                if "transcript" in response:
                    print(f"   📝 转录: {response['transcript']}")
        
        print(f"\n✅ 测试完成！智能音频分类系统评估得分: {total_score/max_score*100:.1f}%")
        
    except KeyboardInterrupt:
        print("\n⏹️ 用户中断测试")
    except Exception as e:
        print(f"\n❌ 测试过程中出错: {e}")
    finally:
        listen_task.cancel()
        if tester.websocket:
            await tester.websocket.close()
        print("🔌 连接已关闭")

if __name__ == "__main__":
    # 依赖检查
    try:
        import websockets
        import numpy as np
    except ImportError as e:
        print(f"❌ 缺少依赖: {e}")
        print("请运行: pip install websockets numpy")
        exit(1)
    
    # 运行全面测试
    asyncio.run(main())