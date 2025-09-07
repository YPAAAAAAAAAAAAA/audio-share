import SwiftUI

struct EnhancedStackedCards: View {
    @State private var scrollOffset: CGFloat = 0
    @State private var selectedIndex: Int = 0
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    @State private var hapticFeedback = UIImpactFeedbackGenerator(style: .light)
    
    let totalCards = 12
    let cardHeight: CGFloat = 420
    let stackSpacing: CGFloat = 85
    let popOffset: CGFloat = -30
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color.black.opacity(0.95)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            GeometryReader { geo in
                ZStack {
                    ForEach(0..<totalCards, id: \.self) { index in
                        StackedCard(
                            index: index,
                            isSelected: selectedIndex == index && !isDragging,
                            isDragging: isDragging,
                            geometry: geo,
                            scrollOffset: scrollOffset + dragOffset,
                            cardHeight: cardHeight,
                            stackSpacing: stackSpacing,
                            popOffset: popOffset
                        )
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                if selectedIndex == index {
                                    hapticFeedback.impactOccurred(intensity: 0.7)
                                    print("Opening card \(index)")
                                } else {
                                    hapticFeedback.impactOccurred(intensity: 0.5)
                                    selectedIndex = index
                                    centerCard(at: index, in: geo)
                                }
                            }
                        }
                    }
                }
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            isDragging = true
                            dragOffset = value.translation.height * 1.2
                        }
                        .onEnded { value in
                            isDragging = false
                            let velocity = value.predictedEndTranslation.height - value.translation.height
                            
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                                scrollOffset += dragOffset + velocity * 0.2
                                dragOffset = 0
                                
                                let nearest = findNearestCard(offset: scrollOffset, in: geo)
                                selectedIndex = nearest
                                centerCard(at: nearest, in: geo)
                                hapticFeedback.impactOccurred(intensity: 0.3)
                            }
                        }
                )
                
                VStack {
                    Spacer()
                    ScrollIndicator(
                        current: selectedIndex,
                        total: totalCards
                    )
                    .padding(.bottom, 50)
                }
            }
        }
        .onAppear {
            hapticFeedback.prepare()
        }
    }
    
    func findNearestCard(offset: CGFloat, in geometry: GeometryProxy) -> Int {
        let center = geometry.size.height / 2
        let cardPosition = -offset + center - cardHeight / 2
        let index = Int(round(cardPosition / stackSpacing))
        return max(0, min(totalCards - 1, index))
    }
    
    func centerCard(at index: Int, in geometry: GeometryProxy) {
        let center = geometry.size.height / 2
        scrollOffset = center - cardHeight / 2 - CGFloat(index) * stackSpacing
    }
}

struct StackedCard: View {
    let index: Int
    let isSelected: Bool
    let isDragging: Bool
    let geometry: GeometryProxy
    let scrollOffset: CGFloat
    let cardHeight: CGFloat
    let stackSpacing: CGFloat
    let popOffset: CGFloat
    
    var yPosition: CGFloat {
        let base = CGFloat(index) * stackSpacing + scrollOffset
        return isSelected ? base + popOffset : base
    }
    
    var cardScale: CGFloat {
        let center = geometry.size.height / 2
        let cardCenter = yPosition + cardHeight / 2
        let distance = abs(center - cardCenter)
        let normalized = min(distance / (geometry.size.height * 0.4), 1)
        let scale = 1 - (normalized * 0.12)
        return isSelected ? scale * 1.02 : scale
    }
    
    var cardOpacity: Double {
        let center = geometry.size.height / 2
        let cardCenter = yPosition + cardHeight / 2
        let distance = abs(center - cardCenter)
        let normalized = min(distance / (geometry.size.height * 0.8), 1)
        return 1 - (normalized * 0.4)
    }
    
    var cardRotation: Double {
        guard !isSelected else { return 0 }
        let center = geometry.size.height / 2
        let cardCenter = yPosition + cardHeight / 2
        let offset = (cardCenter - center) / geometry.size.height
        return Double(offset * 2)
    }
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.black.opacity(0.05),
                                    Color.black.opacity(0.02)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.5
                        )
                )
            
            VStack(spacing: 0) {
                HStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.black.opacity(0.9), Color.black.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                        .overlay(
                            Text("\(index + 1)")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        )
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Capsule()
                            .fill(Color.black)
                            .frame(width: 140, height: 14)
                        
                        Capsule()
                            .fill(Color.black.opacity(0.25))
                            .frame(width: 90, height: 10)
                    }
                    
                    Spacer()
                    
                    Circle()
                        .strokeBorder(Color.black.opacity(0.1), lineWidth: 2)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Circle()
                                .fill(Color.black)
                                .frame(width: 8, height: 8)
                                .opacity(isSelected ? 1 : 0)
                                .animation(.spring(response: 0.3), value: isSelected)
                        )
                }
                .padding(.horizontal, 28)
                .padding(.top, 28)
                
                Spacer()
                
                VStack(spacing: 14) {
                    ForEach(0..<5) { line in
                        Rectangle()
                            .fill(Color.black.opacity(line == 4 ? 0.08 : 0.12))
                            .frame(height: line == 0 ? 2 : 1)
                            .frame(maxWidth: line == 4 ? 180 : .infinity)
                            .animation(.none)
                    }
                }
                .padding(.horizontal, 28)
                
                Spacer()
                
                HStack(spacing: 16) {
                    ForEach(0..<4) { item in
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                item == 0 ? 
                                Color.black : 
                                Color.black.opacity(0.06)
                            )
                            .frame(width: 65, height: 65)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                            )
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }
        }
        .frame(width: geometry.size.width - 48, height: cardHeight)
        .scaleEffect(cardScale)
        .rotation3DEffect(
            .degrees(cardRotation),
            axis: (x: 1, y: 0, z: 0),
            perspective: 0.5
        )
        .opacity(cardOpacity)
        .shadow(
            color: Color.black.opacity(isSelected ? 0.3 : 0.15),
            radius: isSelected ? 40 : 20,
            x: 0,
            y: isSelected ? 20 : 10
        )
        .offset(y: yPosition)
        .animation(
            isDragging ? .none : .spring(response: 0.4, dampingFraction: 0.75),
            value: yPosition
        )
        .animation(
            .spring(response: 0.35, dampingFraction: 0.8),
            value: isSelected
        )
    }
}

struct ScrollIndicator: View {
    let current: Int
    let total: Int
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Color.white : Color.white.opacity(0.3))
                    .frame(width: index == current ? 24 : 8, height: 8)
                    .animation(.spring(response: 0.3), value: current)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.1))
                .background(
                    .ultraThinMaterial,
                    in: Capsule()
                )
        )
    }
}

struct EnhancedStackedCards_Previews: PreviewProvider {
    static var previews: some View {
        EnhancedStackedCards()
    }
}