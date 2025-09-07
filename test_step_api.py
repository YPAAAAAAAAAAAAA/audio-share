#!/usr/bin/env python3
"""
Step Realtime API 连接测试
使用提供的API密钥测试连接和基本功能
"""

import asyncio
import websockets
import json
import base64
import wave
import numpy as np

API_KEY = "8FyDGELcpTdfh1JNOoePkfXzCtExQHL8DSdEX9UYfl4dCsE77R4WIUOIJqanw0Cl"
WS_URL = "wss://api.stepfun.com/v1/realtime"

class StepRealtimeClient:
    def __init__(self):
        self.websocket = None
        
    async def connect(self):
        """连接到Step Realtime API"""
        try:
            # 创建连接时直接传递header
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
    
    async def send_session_config(self):
        """发送session配置"""
        config = {
            "event_id": "session_config_001",
            "type": "session.update",
            "session": {
                "modalities": ["text", "audio"],
                "instructions": """你是一个专业的语音总结助手。
                当用户说话时，请：
                1. 准确转录中文语音
                2. 用5-10个字总结核心内容
                3. 保持简洁精准
                请使用默认女声与用户交流""",
                "voice": "qingchunshaonv",
                "input_audio_format": "pcm16",
                "output_audio_format": "pcm16",
                "turn_detection": {
                    "type": "server_vad",
                    "threshold": 0.5,
                    "silence_duration_ms": 800
                }
            }
        }
        
        await self.websocket.send(json.dumps(config))
        print("📤 发送session配置")
    
    async def generate_test_audio(self):
        """生成测试音频数据 (模拟用户说话)"""
        # 生成440Hz正弦波，模拟1秒钟的音频
        sample_rate = 16000
        duration = 1.0
        frequency = 440
        
        t = np.linspace(0, duration, int(sample_rate * duration), False)
        audio_data = np.sin(2 * np.pi * frequency * t) * 0.3
        
        # 转换为16位PCM
        audio_int16 = (audio_data * 32767).astype(np.int16)
        audio_bytes = audio_int16.tobytes()
        
        return base64.b64encode(audio_bytes).decode()
    
    async def send_test_audio(self):
        """发送测试音频"""
        base64_audio = await self.generate_test_audio()
        
        # 分块发送音频
        chunk_size = 1600  # 100ms的音频数据
        for i in range(0, len(base64_audio), chunk_size):
            chunk = base64_audio[i:i+chunk_size]
            
            message = {
                "event_id": f"audio_chunk_{i//chunk_size}",
                "type": "input_audio_buffer.append",
                "audio": chunk
            }
            
            await self.websocket.send(json.dumps(message))
            await asyncio.sleep(0.1)  # 模拟实时发送
        
        print("📤 发送测试音频数据")
        
        # 提交音频缓冲区
        commit_message = {
            "event_id": "commit_001",
            "type": "input_audio_buffer.commit"
        }
        await self.websocket.send(json.dumps(commit_message))
        print("✅ 提交音频缓冲区")
    
    async def send_text_message(self, text: str):
        """发送文本消息测试总结功能"""
        # 创建文本消息
        create_message = {
            "event_id": "text_msg_001",
            "type": "conversation.item.create",
            "item": {
                "id": "msg_001",
                "type": "message",
                "role": "user",
                "content": [
                    {
                        "type": "input_text",
                        "text": f"请用5-10个字总结：{text}"
                    }
                ]
            }
        }
        
        await self.websocket.send(json.dumps(create_message))
        
        # 触发响应
        response_message = {
            "event_id": "response_001",
            "type": "response.create"
        }
        await self.websocket.send(json.dumps(response_message))
        
        print(f"📤 发送文本消息: {text}")
    
    async def listen_for_responses(self):
        """监听服务器响应"""
        async for message in self.websocket:
            try:
                data = json.loads(message)
                event_type = data.get("type", "unknown")
                
                print(f"📥 收到事件: {event_type}")
                
                if event_type == "session.created":
                    print("✅ Session创建成功")
                    session = data.get("session", {})
                    print(f"   模型: {session.get('model', 'unknown')}")
                    print(f"   音色: {session.get('voice', 'unknown')}")
                
                elif event_type == "session.updated":
                    print("✅ Session配置更新成功")
                
                elif event_type == "conversation.item.input_audio_transcription.completed":
                    transcript = data.get("transcript", "")
                    print(f"🎤 音频转录完成: {transcript}")
                
                elif event_type == "response.audio_transcript.done":
                    transcript = data.get("transcript", "")
                    print(f"🤖 AI回复转录: {transcript}")
                
                elif event_type == "response.text.done":
                    content = data.get("content", "")
                    print(f"💡 AI总结结果: {content}")
                
                elif event_type == "error":
                    error_info = data.get("error", {})
                    print(f"❌ 错误: {error_info.get('message', 'Unknown error')}")
                
                else:
                    print(f"   详细信息: {json.dumps(data, ensure_ascii=False, indent=2)}")
                    
            except Exception as e:
                print(f"❌ 解析消息失败: {e}")
                print(f"   原始消息: {message}")

async def main():
    """主测试函数"""
    client = StepRealtimeClient()
    
    print("🚀 开始测试Step Realtime API")
    print(f"📡 API密钥: {API_KEY[:20]}...")
    print(f"🔗 WebSocket URL: {WS_URL}")
    print("-" * 50)
    
    # 1. 连接测试
    if not await client.connect():
        print("❌ 连接失败，测试终止")
        return
    
    # 2. 启动响应监听
    listen_task = asyncio.create_task(client.listen_for_responses())
    
    try:
        # 3. 发送配置
        await asyncio.sleep(1)
        await client.send_session_config()
        
        # 4. 等待配置完成
        await asyncio.sleep(2)
        
        # 5. 测试文本总结功能
        print("\n📝 测试文本总结功能:")
        test_texts = [
            "今天下午我和团队开会讨论了新产品的设计方案，大家对用户界面提出了很多建议",
            "刚才去超市买了一些水果和蔬菜，花了大概五十块钱",
            "学习了Python的异步编程，感觉这个概念很有用但需要更多练习"
        ]
        
        for text in test_texts:
            await client.send_text_message(text)
            await asyncio.sleep(5)  # 等待响应
            print()
        
        # 6. 测试音频功能 (如果需要)
        print("\n🎵 测试音频功能:")
        # await client.send_test_audio()
        # await asyncio.sleep(5)
        
        print("\n✅ 测试完成!")
        
    except KeyboardInterrupt:
        print("\n⏹️ 用户中断测试")
    except Exception as e:
        print(f"\n❌ 测试过程中出错: {e}")
    finally:
        listen_task.cancel()
        if client.websocket:
            await client.websocket.close()
        print("🔌 连接已关闭")

if __name__ == "__main__":
    # 安装依赖提示
    try:
        import websockets
        import numpy as np
    except ImportError as e:
        print(f"❌ 缺少依赖: {e}")
        print("请运行: pip install websockets numpy")
        exit(1)
    
    # 运行测试
    asyncio.run(main())