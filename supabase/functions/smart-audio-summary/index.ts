import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from 'npm:@supabase/supabase-js@2'

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
)

// 针对不同场景的优化Prompt模板
const PROMPT_TEMPLATES = {
  daily_life: {
    system: "你是一个生活助手，善于提炼日常生活中的关键信息。请用5-8个字概括语音内容的核心。",
    examples: [
      { input: "今天去超市买了水果和蔬菜", output: "超市购物" },
      { input: "下午和朋友喝咖啡聊了很久", output: "朋友聚会" }
    ]
  },
  
  work_meeting: {
    system: "你是一个会议助手，专门总结工作讨论的要点。用5-8个字提炼会议核心内容。",
    examples: [
      { input: "我们讨论了下个月的项目进度和预算分配", output: "项目进度会议" },
      { input: "需要在周五前完成报告的初稿", output: "报告截止任务" }
    ]
  },
  
  learning_notes: {
    system: "你是一个学习助手，善于提炼学习内容的核心知识点。用5-8个字概括重点。",
    examples: [
      { input: "今天学习了机器学习中的神经网络原理", output: "神经网络学习" },
      { input: "复习了英语语法中的时态用法", output: "英语时态复习" }
    ]
  },
  
  personal_thoughts: {
    system: "你是一个思考伙伴，善于捕捉个人想法和感悟的精髓。用5-8个字概括核心想法。",
    examples: [
      { input: "突然想到一个很有趣的创业点子", output: "创业灵感" },
      { input: "对今天的经历有一些深刻的反思", output: "生活感悟" }
    ]
  }
}

Deno.serve(async (req: Request) => {
  const { audioUrl, recordId, userId } = await req.json()
  
  try {
    // 1. 转录音频
    const transcription = await transcribeAudio(audioUrl)
    
    // 2. 智能分类音频内容
    const audioType = await classifyAudioContent(transcription)
    
    // 3. 选择最佳prompt并生成总结
    const summary = await generateOptimizedSummary(transcription, audioType)
    
    // 4. 生成备选总结（用于A/B测试）
    const alternativeSummary = await generateAlternativeSummary(transcription, audioType)
    
    // 5. 更新数据库
    const { error } = await supabase
      .from('audio_records')
      .update({
        transcription,
        ai_summary: summary,
        alternative_summary: alternativeSummary,
        audio_type: audioType,
        processing_status: 'completed',
        processed_at: new Date().toISOString()
      })
      .eq('id', recordId)
    
    return new Response(JSON.stringify({ 
      success: true, 
      summary,
      audioType,
      confidence: 0.85
    }))
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), { status: 500 })
  }
})

async function transcribeAudio(audioUrl: string): Promise<string> {
  const audioResponse = await fetch(audioUrl)
  const audioBuffer = await audioResponse.arrayBuffer()
  
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

async function classifyAudioContent(text: string): Promise<string> {
  const response = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${Deno.env.get('OPENAI_API_KEY')}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      model: 'gpt-4o-mini',
      messages: [{
        role: 'user',
        content: `请分析这段文本属于以下哪个类别，只返回类别名称：
        
类别选项：
- daily_life: 日常生活、购物、娱乐等
- work_meeting: 工作会议、任务讨论、项目规划等  
- learning_notes: 学习笔记、知识总结、教育内容等
- personal_thoughts: 个人想法、感悟、创意灵感等

文本内容：${text}

返回格式：只返回类别名称，如 daily_life`
      }],
      max_tokens: 20,
      temperature: 0.1
    })
  })
  
  const result = await response.json()
  const category = result.choices[0].message.content.trim()
  
  // 确保返回有效类别
  if (Object.keys(PROMPT_TEMPLATES).includes(category)) {
    return category
  }
  return 'daily_life' // 默认类别
}

async function generateOptimizedSummary(text: string, audioType: string): Promise<string> {
  const template = PROMPT_TEMPLATES[audioType] || PROMPT_TEMPLATES.daily_life
  
  // 构建few-shot prompt
  let prompt = template.system + "\n\n示例：\n"
  template.examples.forEach(example => {
    prompt += `输入：${example.input}\n输出：${example.output}\n\n`
  })
  prompt += `现在请总结：${text}\n输出：`
  
  const response = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${Deno.env.get('OPENAI_API_KEY')}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      model: 'gpt-4o-mini',
      messages: [{ role: 'user', content: prompt }],
      max_tokens: 20,
      temperature: 0.3
    })
  })
  
  const result = await response.json()
  return result.choices[0].message.content.trim()
}

async function generateAlternativeSummary(text: string, audioType: string): Promise<string> {
  // 使用不同的温度参数生成备选总结
  const template = PROMPT_TEMPLATES[audioType] || PROMPT_TEMPLATES.daily_life
  
  const response = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${Deno.env.get('OPENAI_API_KEY')}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      model: 'gpt-4o-mini',
      messages: [
        { role: 'system', content: template.system },
        { role: 'user', content: `请总结这段话：${text}` }
      ],
      max_tokens: 20,
      temperature: 0.7 // 更高的温度生成更有创意的总结
    })
  })
  
  const result = await response.json()
  return result.choices[0].message.content.trim()
}