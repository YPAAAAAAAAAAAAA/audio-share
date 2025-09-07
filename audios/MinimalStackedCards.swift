import SwiftUI

struct MinimalStackedCards: View {
    @State private var offset: CGFloat = 0
    @State private var activeCard: Int = 0
    @State private var dragValue: CGFloat = 0
    
    let cards = Array(0..<8)
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            GeometryReader { geo in
                ZStack {
                    ForEach(cards, id: \.self) { i in
                        MinimalCard(
                            index: i,
                            active: activeCard == i,
                            offset: offset + dragValue,
                            screenHeight: geo.size.height
                        )
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                if activeCard == i {
                                    print("Show details for card \(i)")
                                } else {
                                    activeCard = i
                                    let centerY = geo.size.height / 2
                                    offset = -CGFloat(i) * 100 + centerY - 200
                                }
                            }
                        }
                    }
                }
                .gesture(
                    DragGesture()
                        .onChanged { drag in
                            dragValue = drag.translation.height
                        }
                        .onEnded { drag in
                            withAnimation(.interactiveSpring()) {
                                offset += dragValue
                                dragValue = 0
                                
                                let centerY = geo.size.height / 2
                                let calculation = (-offset + centerY - 200) / 100
                                let roundedIndex = Int(round(calculation))
                                let cardIndex = max(0, min(cards.count - 1, roundedIndex))
                                activeCard = cardIndex
                                offset = -CGFloat(cardIndex) * 100 + centerY - 200
                            }
                        }
                )
            }
        }
    }
}

struct MinimalCard: View {
    let index: Int
    let active: Bool
    let offset: CGFloat
    let screenHeight: CGFloat
    
    var position: CGFloat {
        let basePosition = CGFloat(index) * 100 + offset
        let activeOffset: CGFloat = active ? -25 : 0
        return basePosition + activeOffset
    }
    
    var scale: CGFloat {
        let center = screenHeight / 2
        let distance = abs(position + 200 - center)
        return max(0.88, 1 - distance / 1000)
    }
    
    var opacity: Double {
        let center = screenHeight / 2
        let distance = abs(position + 200 - center)
        return max(0.4, 1 - distance / 600)
    }
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
            
            VStack {
                HStack {
                    Text("CARD")
                        .font(.system(size: 14, weight: .black))
                        .tracking(3)
                        .foregroundColor(.black.opacity(0.2))
                    
                    Spacer()
                    
                    Text("\(index + 1)")
                        .font(.system(size: 40, weight: .thin))
                        .foregroundColor(.black.opacity(0.15))
                }
                .padding(30)
                
                Spacer()
                
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.black)
                        .frame(width: 60)
                    Rectangle()
                        .fill(Color.black.opacity(0.8))
                        .frame(width: 60)
                    Rectangle()
                        .fill(Color.black.opacity(0.6))
                        .frame(width: 60)
                    Rectangle()
                        .fill(Color.black.opacity(0.4))
                        .frame(width: 60)
                    Rectangle()
                        .fill(Color.black.opacity(0.2))
                }
                .frame(height: 80)
            }
        }
        .frame(width: 320, height: 400)
        .scaleEffect(scale)
        .opacity(opacity)
        .shadow(color: .white.opacity(active ? 0.1 : 0.05), radius: active ? 30 : 15)
        .offset(y: position)
    }
}

struct MinimalStackedCards_Previews: PreviewProvider {
    static var previews: some View {
        MinimalStackedCards()
    }
}