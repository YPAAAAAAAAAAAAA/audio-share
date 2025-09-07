import SwiftUI

struct StackedCardsView: View {
    @State private var scrollOffset: CGFloat = 0
    @State private var selectedIndex: Int? = nil
    @State private var dragOffset: CGFloat = 0
    
    let cards = Array(0..<10)
    let cardHeight: CGFloat = 400
    let cardSpacing: CGFloat = 80
    let popupOffset: CGFloat = -20
    
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            
            GeometryReader { geometry in
                ZStack {
                    ForEach(cards.indices, id: \.self) { index in
                        CardView(
                            index: index,
                            isSelected: selectedIndex == index,
                            geometry: geometry,
                            scrollOffset: scrollOffset + dragOffset,
                            cardHeight: cardHeight,
                            cardSpacing: cardSpacing,
                            popupOffset: popupOffset
                        )
                        .onTapGesture {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                if selectedIndex == index {
                                    print("Card \(index) tapped - show full info")
                                } else {
                                    selectedIndex = index
                                    snapToCard(index: index, geometry: geometry)
                                }
                            }
                        }
                    }
                }
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dragOffset = value.translation.height
                            selectedIndex = nil
                        }
                        .onEnded { value in
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                scrollOffset += dragOffset
                                dragOffset = 0
                                
                                let totalOffset = scrollOffset
                                let nearestCardIndex = getNearestCardIndex(offset: totalOffset, geometry: geometry)
                                snapToCard(index: nearestCardIndex, geometry: geometry)
                                selectedIndex = nearestCardIndex
                            }
                        }
                )
            }
        }
        .preferredColorScheme(.dark)
    }
    
    func getNearestCardIndex(offset: CGFloat, geometry: GeometryProxy) -> Int {
        let centerY = geometry.size.height / 2
        let adjustedOffset = -offset + centerY - cardHeight / 2
        let index = Int(round(adjustedOffset / cardSpacing))
        return max(0, min(cards.count - 1, index))
    }
    
    func snapToCard(index: Int, geometry: GeometryProxy) {
        let centerY = geometry.size.height / 2
        let targetOffset = centerY - cardHeight / 2 - CGFloat(index) * cardSpacing
        scrollOffset = targetOffset
    }
}

struct CardView: View {
    let index: Int
    let isSelected: Bool
    let geometry: GeometryProxy
    let scrollOffset: CGFloat
    let cardHeight: CGFloat
    let cardSpacing: CGFloat
    let popupOffset: CGFloat
    
    var cardOffset: CGFloat {
        let baseOffset = CGFloat(index) * cardSpacing + scrollOffset
        return isSelected ? baseOffset + popupOffset : baseOffset
    }
    
    var scale: CGFloat {
        let centerY = geometry.size.height / 2
        let cardCenterY = cardOffset + cardHeight / 2
        let distance = abs(centerY - cardCenterY)
        let maxDistance = geometry.size.height / 2
        let normalizedDistance = min(distance / maxDistance, 1)
        return 1 - (normalizedDistance * 0.1)
    }
    
    var opacity: Double {
        let centerY = geometry.size.height / 2
        let cardCenterY = cardOffset + cardHeight / 2
        let distance = abs(centerY - cardCenterY)
        let maxDistance = geometry.size.height
        let normalizedDistance = min(distance / maxDistance, 1)
        return 1 - (normalizedDistance * 0.3)
    }
    
    var shadowRadius: CGFloat {
        isSelected ? 30 : 15
    }
    
    var body: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.95),
                        Color.white.opacity(0.85)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.black.opacity(0.1), lineWidth: 1)
            )
            .overlay(
                VStack(spacing: 16) {
                    HStack {
                        Circle()
                            .fill(Color.black.opacity(0.1))
                            .frame(width: 50, height: 50)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.black.opacity(0.8))
                                .frame(width: 120, height: 12)
                            
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.black.opacity(0.3))
                                .frame(width: 80, height: 10)
                        }
                        
                        Spacer()
                        
                        Text("\(index + 1)")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundColor(.black.opacity(0.15))
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(0..<4) { line in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.black.opacity(0.15))
                                .frame(height: 8)
                                .frame(maxWidth: line == 3 ? 200 : .infinity)
                        }
                    }
                    .padding(.horizontal, 24)
                    
                    Spacer()
                    
                    HStack(spacing: 20) {
                        ForEach(0..<3) { _ in
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.black.opacity(0.08))
                                .frame(width: 80, height: 80)
                        }
                    }
                    .padding(.bottom, 24)
                }
            )
            .frame(width: geometry.size.width - 40, height: cardHeight)
            .scaleEffect(scale)
            .opacity(opacity)
            .shadow(color: .black.opacity(0.2), radius: shadowRadius, x: 0, y: 10)
            .offset(y: cardOffset)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isSelected)
    }
}

struct StackedCardsView_Previews: PreviewProvider {
    static var previews: some View {
        StackedCardsView()
    }
}