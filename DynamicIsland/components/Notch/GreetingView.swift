import SwiftUI

struct GreetingView: View {
    let name: String
    let message: String
    
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "hand.wave.fill")
                .foregroundColor(.yellow)
                .font(.system(size: 16))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text(message)
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
