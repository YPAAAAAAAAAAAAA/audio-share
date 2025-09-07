#!/usr/bin/env python3
"""
语音识别+LLM微调数据处理Pipeline
"""

import json
import whisper
import openai
from pathlib import Path
from typing import List, Dict
import asyncio
from supabase import create_client, Client

class AudioFineTuningPipeline:
    def __init__(self, supabase_url: str, supabase_key: str, openai_key: str):
        self.supabase: Client = create_client(supabase_url, supabase_key)
        openai.api_key = openai_key
        self.whisper_model = whisper.load_model("base")
    
    async def collect_training_data(self, user_id: str) -> List[Dict]:
        """从Supabase收集用户的音频数据"""
        response = self.supabase.table("audio_records").select("*").eq("user_id", user_id).execute()
        
        training_data = []
        for record in response.data:
            # 下载音频文件
            audio_data = await self.download_audio(record["audio_url"])
            
            # Whisper转录
            transcription = self.whisper_model.transcribe(audio_data)["text"]
            
            # 构造训练样本
            training_sample = {
                "messages": [
                    {"role": "system", "content": "你是一个专业的语音内容总结助手，能够将语音转录文本总结为5-10个字的简洁标题。"},
                    {"role": "user", "content": f"请总结这段话：{transcription}"},
                    {"role": "assistant", "content": self.generate_expected_summary(transcription)}
                ]
            }
            training_data.append(training_sample)
        
        return training_data
    
    def generate_expected_summary(self, text: str) -> str:
        """生成期望的总结（基线模型）"""
        response = openai.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": "用5-10个中文字总结核心内容"},
                {"role": "user", "content": text}
            ],
            max_tokens=20
        )
        return response.choices[0].message.content.strip()
    
    async def prepare_fine_tuning_file(self, training_data: List[Dict]) -> str:
        """准备OpenAI微调文件"""
        file_path = "training_data.jsonl"
        with open(file_path, "w", encoding="utf-8") as f:
            for sample in training_data:
                f.write(json.dumps(sample, ensure_ascii=False) + "\n")
        
        # 上传到OpenAI
        with open(file_path, "rb") as f:
            response = openai.files.create(file=f, purpose="fine-tune")
        
        return response.id
    
    async def start_fine_tuning(self, training_file_id: str) -> str:
        """启动微调作业"""
        job = openai.fine_tuning.jobs.create(
            training_file=training_file_id,
            model="gpt-4o-mini",
            suffix="audio-summary-v1",
            hyperparameters={
                "n_epochs": 3,
                "batch_size": 4,
                "learning_rate_multiplier": 0.1
            }
        )
        return job.id
    
    async def monitor_training(self, job_id: str):
        """监控训练进度"""
        while True:
            job = openai.fine_tuning.jobs.retrieve(job_id)
            print(f"状态: {job.status}")
            
            if job.status == "succeeded":
                print(f"微调完成! 模型ID: {job.fine_tuned_model}")
                return job.fine_tuned_model
            elif job.status == "failed":
                print(f"微调失败: {job.error}")
                return None
            
            await asyncio.sleep(60)  # 每分钟检查一次

async def main():
    pipeline = AudioFineTuningPipeline(
        supabase_url="YOUR_SUPABASE_URL",
        supabase_key="YOUR_SUPABASE_KEY", 
        openai_key="YOUR_OPENAI_KEY"
    )
    
    # 1. 收集训练数据
    training_data = await pipeline.collect_training_data("user_id_here")
    print(f"收集到 {len(training_data)} 个训练样本")
    
    # 2. 准备微调文件
    file_id = await pipeline.prepare_fine_tuning_file(training_data)
    print(f"训练文件上传完成: {file_id}")
    
    # 3. 启动微调
    job_id = await pipeline.start_fine_tuning(file_id)
    print(f"微调作业启动: {job_id}")
    
    # 4. 监控训练
    model_id = await pipeline.monitor_training(job_id)
    if model_id:
        print(f"微调模型可用: {model_id}")

if __name__ == "__main__":
    asyncio.run(main())