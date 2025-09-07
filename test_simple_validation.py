#!/usr/bin/env python3
"""
简化版验证测试 - 确保基本功能正常
"""

import asyncio
import websockets
import json
import time

API_KEY = "8FyDGELcpTdfh1JNOoePkfXzCtExQHL8DSdEX9UYfl4dCsE77R4WIUOIJqanw0Cl"
WS_URL = "wss://api.stepfun.com/v1/realtime"

async def simple_test():
    """简单测试连接和基本功能"""
    print("🔍 简化版API功能验证")
    print("=" * 40)
    
    try:
        # 连接
        websocket = await websockets.connect(
            f"{WS_URL}?model=step-audio-2-mini",
            additional_headers={"Authorization": f"Bearer {API_KEY}"}
        )
        print("✅ 连接成功")
        
        # 监听任务
        async def listen():
            responses = []
            async for message in websocket:
                try:
                    data = json.loads(message)
                    event_type = data.get("type")
                    
                    if event_type == "session.created":
                        print("✅ Session已创建")
                    elif event_type == "session.updated": 
                        print("✅ 配置已更新")
                    elif event_type == "response.text.done":
                        content = data.get("content", "")
                        print(f"💡 AI回复: {content}")
                        print(f"   字数: {len(content)}")
                        responses.append(content)
                        if len(responses) >= 2:  # 收到2个回复后结束
                            break
                    elif event_type == "error":
                        print(f"❌ 错误: {data.get('error', {})}")
                        
                except Exception as e:
                    print(f"❌ 解析错误: {e}")
            
            return responses
        
        listen_task = asyncio.create_task(listen())
        
        # 等待初始化
        await asyncio.sleep(1)
        
        # 发送配置
        config = {
            "type": "session.update",
            "session": {
                "modalities": ["text", "audio"],
                "instructions": "你是音频分析助手。请用3-6个字总结用户输入的内容特征。",
                "voice": "qingchunshaonv",
                "input_audio_format": "pcm16",
                "output_audio_format": "pcm16"
            }
        }
        
        await websocket.send(json.dumps(config))
        print("📤 发送基础配置")
        await asyncio.sleep(1.5)
        
        # 测试案例
        test_cases = [
            "今天开会讨论新项目",
            "外面风声很大"
        ]
        
        for i, text in enumerate(test_cases, 1):
            print(f"\n🧪 测试 {i}: {text}")
            
            # 创建消息
            create_msg = {
                "type": "conversation.item.create", 
                "item": {
                    "type": "message",
                    "role": "user",
                    "content": [{"type": "input_text", "text": text}]
                }
            }
            await websocket.send(json.dumps(create_msg))
            
            # 请求响应
            response_msg = {"type": "response.create"}
            await websocket.send(json.dumps(response_msg))
            
            await asyncio.sleep(4)  # 等待响应
        
        # 等待所有响应
        responses = await asyncio.wait_for(listen_task, timeout=15)
        
        print(f"\n📊 测试结果:")
        print(f"收到响应数: {len(responses)}")
        
        for i, resp in enumerate(responses, 1):
            char_count = len(resp)
            is_good_length = 3 <= char_count <= 8
            print(f"{i}. {resp} ({char_count}字) {'✅' if is_good_length else '⚠️'}")
        
        print("\n🎉 基础功能验证完成!")
        
    except Exception as e:
        print(f"❌ 测试失败: {e}")
    finally:
        try:
            await websocket.close()
        except:
            pass
        print("🔌 连接关闭")

if __name__ == "__main__":
    asyncio.run(simple_test())