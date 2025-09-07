// PromptFeedbackManager.swift
// 用户反馈收集系统

import Foundation
import Supabase

struct SummaryFeedback {
    let recordId: UUID
    let originalSummary: String
    let userRating: Int // 1-5星评分
    let userCorrection: String? // 用户修正的总结
    let feedbackType: String // "good", "bad", "corrected"
    let timestamp: Date
}

class PromptFeedbackManager {
    static let shared = PromptFeedbackManager()
    private let supabase = SupabaseManager.shared.client
    
    // 收集用户反馈
    func submitFeedback(
        recordId: UUID,
        originalSummary: String,
        rating: Int,
        correction: String? = nil
    ) async throws {
        let feedbackType: String
        if let correction = correction {
            feedbackType = "corrected"
        } else if rating >= 4 {
            feedbackType = "good"
        } else {
            feedbackType = "bad"
        }
        
        let feedback = [
            "record_id": recordId.uuidString,
            "original_summary": originalSummary,
            "user_rating": rating,
            "user_correction": correction ?? "",
            "feedback_type": feedbackType,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ] as [String: Any]
        
        _ = try await supabase
            .from("summary_feedback")
            .insert(feedback)
            .execute()
        
        print("✅ 反馈已提交")
    }
    
    // A/B测试：随机显示备选总结
    func shouldShowAlternativeSummary() -> Bool {
        return Bool.random() // 50%概率显示备选总结
    }
    
    // 收集A/B测试结果
    func submitABTestResult(
        recordId: UUID,
        shownSummary: String,
        alternativeSummary: String,
        userPreference: String // "shown", "alternative", "both_good", "both_bad"
    ) async throws {
        let abTestResult = [
            "record_id": recordId.uuidString,
            "shown_summary": shownSummary,
            "alternative_summary": alternativeSummary,
            "user_preference": userPreference,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ] as [String: Any]
        
        _ = try await supabase
            .from("ab_test_results")
            .insert(abTestResult)
            .execute()
    }
}

// UI组件：总结反馈界面
struct SummaryFeedbackView: View {
    let recordId: UUID
    let summary: String
    let alternativeSummary: String?
    
    @State private var rating: Int = 5
    @State private var correction: String = ""
    @State private var showingCorrection = false
    @State private var showingABTest = false
    
    var body: some View {
        VStack(spacing: 16) {
            // 主要总结
            VStack(alignment: .leading, spacing: 8) {
                Text("AI总结")
                    .font(.headline)
                
                Text(summary)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                
                // 评分
                HStack {
                    Text("准确度:")
                    ForEach(1...5, id: \.self) { star in
                        Button(action: {
                            rating = star
                        }) {
                            Image(systemName: star <= rating ? "star.fill" : "star")
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
            
            // A/B测试：备选总结
            if let alternative = alternativeSummary, !showingABTest {
                Button("查看其他总结建议") {
                    showingABTest = true
                }
            }
            
            if showingABTest, let alternative = alternativeSummary {
                VStack(alignment: .leading, spacing: 8) {
                    Text("备选总结")
                        .font(.headline)
                    
                    Text(alternative)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    
                    HStack {
                        Button("更喜欢原总结") {
                            Task {
                                try await PromptFeedbackManager.shared.submitABTestResult(
                                    recordId: recordId,
                                    shownSummary: summary,
                                    alternativeSummary: alternative,
                                    userPreference: "shown"
                                )
                            }
                        }
                        
                        Button("更喜欢备选总结") {
                            Task {
                                try await PromptFeedbackManager.shared.submitABTestResult(
                                    recordId: recordId,
                                    shownSummary: summary,
                                    alternativeSummary: alternative,
                                    userPreference: "alternative"
                                )
                            }
                        }
                    }
                }
            }
            
            // 修正建议
            if showingCorrection {
                VStack(alignment: .leading, spacing: 8) {
                    Text("您的修正建议")
                        .font(.headline)
                    
                    TextField("输入更好的总结", text: $correction)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
            }
            
            // 操作按钮
            HStack {
                if rating < 4 {
                    Button(showingCorrection ? "隐藏修正" : "提供修正") {
                        showingCorrection.toggle()
                    }
                }
                
                Button("提交反馈") {
                    Task {
                        try await PromptFeedbackManager.shared.submitFeedback(
                            recordId: recordId,
                            originalSummary: summary,
                            rating: rating,
                            correction: correction.isEmpty ? nil : correction
                        )
                    }
                }
                .disabled(rating == 0)
            }
        }
        .padding()
    }
}