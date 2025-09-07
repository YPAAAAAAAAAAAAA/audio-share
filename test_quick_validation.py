#!/usr/bin/env python3
"""
快速验证环境音vs人声分类 + 5-10秒总结
"""

import asyncio
import websockets
import json
import time

API_KEY = "8FyDGELcpTdfh1JNOoePkfXzCtExQHL8DSdEX9UYfl4dCsE77R4WIUOIJqanw0Cl"
WS_URL = "wss://api.stepfun.com/v1/realtime"

class QuickValidator:
    def __init__(self):
        self.websocket = None
        self.test_start_time = None
        
    async def connect(self):
        """连接到API"""
        try:
            self.websocket = await websockets.connect(
                f"{WS_URL}?model=step-audio-2-mini",
                additional_headers={"Authorization": f"Bearer {API_KEY}"}
            )
            print("✅ 连接成功")
            return True
        except Exception as e:
            print(f"❌ 连接失败: {e}")
            return False
    
    async def test_environment_detection(self):
        """测试环境音检测配置"""
        config = {
            "event_id": "env_test",
            "type": "session.update",
            "session": {
                "modalities": ["text", "audio"],
                "instructions": """你是环境音分析助手。听到声音后：
1. 判断是环境音还是人声
2. 用3-6字描述特征
3. 如果是人声，回复"检测到人声"
4. 如果是环境音，描述环境类型""",
                "voice": "qingchunshaonv",
                "input_audio_format": "pcm16",
                "output_audio_format": "pcm16",
                "turn_detection": {
                    "type": "server_vad",
                    "threshold": 0.3,
                    "silence_duration_ms": 300
                }
            }
        }
        
        await self.websocket.send(json.dumps(config))
        print("📤 发送环境音检测配置")
        await asyncio.sleep(2)
    
    async def test_text_scenarios(self):
        """发送文本测试不同场景的总结能力"""
        test_cases = [
            ("环境音场景", "刚才听到外面有风声和鸟叫声，像是自然环境的声音"),
            ("人声场景", "用户刚才说要去开会讨论新项目的进展"),
            ("混合场景", "背景有音乐声，但用户在说话要订餐"),
            ("机械音场景", "听到机器运转的嗡嗡声和齿轮转动")
        ]
        
        for test_name, text in test_cases:
            print(f"\n🧪 测试: {test_name}")
            self.test_start_time = time.time()
            
            # 创建文本消息
            create_message = {
                "event_id": f"test_{test_name}",
                "type": "conversation.item.create",
                "item": {
                    "id": f"msg_{test_name}",
                    "type": "message",
                    "role": "user",
                    "content": [{"type": "input_text", "text": text}]
                }
            }
            
            await self.websocket.send(json.dumps(create_message))
            
            # 触发响应
            response_message = {
                "event_id": f"response_{test_name}",
                "type": "response.create"
            }
            await self.websocket.send(json.dumps(response_message))
            
            print(f"📤 发送: {text}")
            await asyncio.sleep(8)  # 等待响应
    
    async def listen_responses(self):
        """监听响应"""
        response_count = 0
        async for message in self.websocket:
            try:
                data = json.loads(message)
                event_type = data.get("type", "unknown")
                
                if event_type == "session.created":
                    print("✅ Session创建")
                    
                elif event_type == "session.updated":
                    print("✅ 配置更新成功")
                    
                elif event_type == "response.text.done":
                    content = data.get("content", "")
                    if self.test_start_time:
                        response_time = time.time() - self.test_start_time
                        print(f"💡 AI总结 ({response_time:.1f}秒): {content}")
                        print(f"   字数: {len(content)}字")
                        
                        # 评估回复质量
                        if 3 <= len(content) <= 10:
                            print(f"   ✅ 长度合适 (3-10字)")
                        else:
                            print(f"   ⚠️ 长度不当 (应为3-10字)")
                        
                        if response_time <= 10:
                            print(f"   ✅ 响应及时 (<10秒)")
                        else:
                            print(f"   ⚠️ 响应较慢 (>10秒)")
                        
                        response_count += 1
                        if response_count >= 4:  # 完成所有测试
                            print("\n🎉 所有测试完成!")
                            return
                    
                elif event_type == "error":
                    error_info = data.get("error", {})
                    print(f"❌ 错误: {error_info.get('message')}")
                    
            except Exception as e:
                print(f"❌ 解析失败: {e}")

async def main():
    """快速验证主函数"""
    validator = QuickValidator()
    
    print("🚀 快速验证环境音vs人声分类")
    print("=" * 50)
    
    if not await validator.connect():
        return
    
    # 启动监听
    listen_task = asyncio.create_task(validator.listen_responses())
    
    try:
        await validator.test_environment_detection()
        await validator.test_text_scenarios()
        
        # 等待所有响应
        await listen_task
        
    except Exception as e:
        print(f"❌ 测试出错: {e}")
    finally:
        listen_task.cancel()
        if validator.websocket:
            await validator.websocket.close()
        print("🔌 连接关闭")

if __name__ == "__main__":
    asyncio.run(main())