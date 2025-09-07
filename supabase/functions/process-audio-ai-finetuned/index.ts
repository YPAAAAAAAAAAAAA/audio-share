import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from 'npm:@supabase/supabase-js@2'

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
)

Deno.serve(async (req: Request) => {
  const { audioUrl, recordId, userId } = await req.json()
  
  try {
    // 1. 转录音频
    const transcription = await transcribeAudio(audioUrl)
    
    // 2. 使用微调模型生成总结
    const summary = await generateFinetunedSummary(transcription, userId)
    
    // 3. A/B测试 - 同时生成基线总结进行对比
    const baselineSummary = await generateBaselineSummary(transcription)
    
    // 4. 更新数据库
    const { error } = await supabase
      .from('audio_records')
      .update({
        transcription,
        ai_summary: summary,
        baseline_summary: baselineSummary, // 用于A/B测试
        processing_status: 'completed',
        processed_at: new Date().toISOString(),
        model_version: 'finetuned-v1'
      })
      .eq('id', recordId)
    
    // 5. 记录性能指标
    await logModelPerformance(recordId, {
      transcription_length: transcription.length,
      summary_length: summary.length,
      processing_time: Date.now(),
      model_type: 'finetuned'
    })
    
    return new Response(JSON.stringify({ 
      success: true, 
      summary,
      model_version: 'finetuned-v1'
    }))
  } catch (error) {
    await supabase
      .from('audio_records')
      .update({ processing_status: 'failed' })
      .eq('id', recordId)
    
    return new Response(JSON.stringify({ error: error.message }), { status: 500 })
  }
})

async function transcribeAudio(audioUrl: string): Promise<string> {
  // 下载音频文件
  const audioResponse = await fetch(audioUrl)
  const audioBuffer = await audioResponse.arrayBuffer()
  
  // 调用Whisper API
  const formData = new FormData()
  formData.append('file', new Blob([audioBuffer]), 'audio.m4a')
  formData.append('model', 'whisper-1')
  formData.append('language', 'zh')
  
  const response = await fetch('https://api.openai.com/v1/audio/transcriptions', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${Deno.env.get('OPENAI_API_KEY')}`
    },
    body: formData
  })
  
  const result = await response.json()
  return result.text
}

async function generateFinetunedSummary(text: string, userId: string): Promise<string> {
  // 获取用户的微调模型ID
  const { data: userModel } = await supabase
    .from('user_models')
    .select('finetuned_model_id')
    .eq('user_id', userId)
    .single()
  
  const modelId = userModel?.finetuned_model_id || 'gpt-4o-mini' // 回退到基础模型
  
  const response = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${Deno.env.get('OPENAI_API_KEY')}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      model: modelId,
      messages: [
        {
          role: 'system', 
          content: '你是一个专业的语音内容总结助手，能够将语音转录文本总结为5-10个字的简洁标题。'
        },
        {
          role: 'user',
          content: `请总结这段话：${text}`
        }
      ],
      max_tokens: 20,
      temperature: 0.3
    })
  })
  
  const result = await response.json()
  return result.choices[0].message.content.trim()
}

async function generateBaselineSummary(text: string): Promise<string> {
  // 基线模型总结，用于A/B测试对比
  const response = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${Deno.env.get('OPENAI_API_KEY')}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      model: 'gpt-4o-mini',
      messages: [
        {
          role: 'user',
          content: `用5-10个中文字总结这段话的核心内容：${text}`
        }
      ],
      max_tokens: 20
    })
  })
  
  const result = await response.json()
  return result.choices[0].message.content.trim()
}

async function logModelPerformance(recordId: string, metrics: any) {
  await supabase
    .from('model_performance_logs')
    .insert({
      record_id: recordId,
      metrics,
      timestamp: new Date().toISOString()
    })
}