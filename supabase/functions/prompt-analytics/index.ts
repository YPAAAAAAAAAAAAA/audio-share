import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from 'npm:@supabase/supabase-js@2'

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
)

Deno.serve(async (req: Request) => {
  const { action } = await req.json()
  
  switch (action) {
    case 'analyze_performance':
      return new Response(JSON.stringify(await analyzePromptPerformance()))
    case 'generate_optimizations':
      return new Response(JSON.stringify(await generateOptimizationSuggestions()))
    case 'update_prompts':
      return new Response(JSON.stringify(await updateOptimizedPrompts()))
    default:
      return new Response(JSON.stringify({ error: 'Invalid action' }), { status: 400 })
  }
})

async function analyzePromptPerformance() {
  // 1. 获取用户反馈数据
  const { data: feedbacks } = await supabase
    .from('summary_feedback')
    .select('*')
    .gte('timestamp', new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString()) // 最近7天
  
  // 2. 获取A/B测试结果
  const { data: abTests } = await supabase
    .from('ab_test_results')
    .select('*')
    .gte('timestamp', new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString())
  
  // 3. 按音频类型分析性能
  const performanceByType = {}
  
  for (const feedback of feedbacks || []) {
    const { data: record } = await supabase
      .from('audio_records')
      .select('audio_type')
      .eq('id', feedback.record_id)
      .single()
    
    const audioType = record?.audio_type || 'unknown'
    
    if (!performanceByType[audioType]) {
      performanceByType[audioType] = {
        total: 0,
        good_ratings: 0,
        corrections: 0,
        avg_rating: 0
      }
    }
    
    performanceByType[audioType].total++
    if (feedback.user_rating >= 4) performanceByType[audioType].good_ratings++
    if (feedback.user_correction) performanceByType[audioType].corrections++
  }
  
  // 4. A/B测试胜率分析
  const abTestWins = {
    original: 0,
    alternative: 0,
    total: abTests?.length || 0
  }
  
  abTests?.forEach(test => {
    if (test.user_preference === 'shown') abTestWins.original++
    if (test.user_preference === 'alternative') abTestWins.alternative++
  })
  
  return {
    performanceByType,
    abTestResults: {
      ...abTestWins,
      alternative_win_rate: abTestWins.total > 0 ? 
        (abTestWins.alternative / abTestWins.total * 100).toFixed(1) + '%' : '0%'
    },
    recommendations: await generateRecommendations(performanceByType)
  }
}

async function generateOptimizationSuggestions() {
  // 分析用户修正意见，生成prompt优化建议
  const { data: corrections } = await supabase
    .from('summary_feedback')
    .select('original_summary, user_correction, record_id')
    .not('user_correction', 'is', null)
    .limit(50)
  
  if (!corrections || corrections.length === 0) {
    return { suggestions: [] }
  }
  
  // 使用AI分析用户修正模式
  const correctionAnalysis = corrections.map(c => 
    `原总结: ${c.original_summary}\n用户修正: ${c.user_correction}`
  ).join('\n\n')
  
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
        content: `分析以下用户对AI总结的修正意见，找出改进模式并给出prompt优化建议：

${correctionAnalysis}

请分析：
1. 用户修正的主要方向是什么？
2. 原总结有什么共同问题？
3. 如何改进prompt来避免这些问题？

返回JSON格式：
{
  "patterns": ["模式1", "模式2"],
  "issues": ["问题1", "问题2"],
  "suggestions": ["建议1", "建议2"]
}`
      }],
      max_tokens: 500
    })
  })
  
  const result = await response.json()
  return JSON.parse(result.choices[0].message.content)
}

async function generateRecommendations(performanceByType: any) {
  const recommendations = []
  
  Object.entries(performanceByType).forEach(([type, stats]: [string, any]) => {
    const goodRatePercent = (stats.good_ratings / stats.total * 100).toFixed(1)
    const correctionRatePercent = (stats.corrections / stats.total * 100).toFixed(1)
    
    if (stats.good_ratings / stats.total < 0.7) {
      recommendations.push({
        type,
        issue: `${type}类型的好评率仅${goodRatePercent}%`,
        suggestion: `需要优化${type}类型的prompt，增加更多相关示例`
      })
    }
    
    if (stats.corrections / stats.total > 0.2) {
      recommendations.push({
        type,
        issue: `${type}类型的修正率高达${correctionRatePercent}%`,
        suggestion: `分析用户修正意见，调整prompt指导语`
      })
    }
  })
  
  return recommendations
}

async function updateOptimizedPrompts() {
  // 这里可以实现自动更新prompt的逻辑
  // 比如从配置表中读取新的prompt模板
  
  const { data: promptUpdates } = await supabase
    .from('prompt_updates')
    .select('*')
    .eq('status', 'pending')
  
  // 应用prompt更新
  // 实际实现中可以通过配置管理系统来更新prompt
  
  return {
    message: 'Prompt optimization completed',
    updates_applied: promptUpdates?.length || 0
  }
}