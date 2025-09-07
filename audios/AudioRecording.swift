import Foundation

// MARK: - 数据模型
struct AudioRecording: Identifiable, Equatable {
    let id = UUID()
    let duration: Int // 秒
    var title: String  // Changed to var for AI summary updates
    let timestamp: Date
    var isProcessing: Bool = false
    var hasAIAnalysis: Bool = false
    var localURL: URL? = nil
    var remoteURL: String? = nil
    var supabaseId: UUID? = nil  // Store Supabase record ID for proper deletion
    
    // 根据时长确定网格尺寸
    var gridSize: GridSize {
        switch duration {
        case 0..<30:
            return GridSize(columns: 1, rows: 1) // 1x1
        case 30..<120:
            return GridSize(columns: 2, rows: 1) // 2x1
        default:
            return GridSize(columns: 2, rows: 2) // 2x2
        }
    }
    
    var cardSize: CardSize {
        switch duration {
        case 0..<30: return .small
        case 30..<120: return .medium
        default: return .large
        }
    }
    
    var durationText: String {
        if duration < 60 {
            return "\(duration)s"
        } else {
            let minutes = duration / 60
            let seconds = duration % 60
            return seconds == 0 ? "\(minutes)min" : "\(minutes)m \(seconds)s"
        }
    }
    
    // Removed categoryColor - using black/white only
}

struct GridSize {
    let columns: Int
    let rows: Int
}

enum CardSize {
    case small, medium, large
}