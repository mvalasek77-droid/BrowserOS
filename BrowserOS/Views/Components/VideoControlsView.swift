import SwiftUI

// MARK: - Video Scrubber
// Custom slider for watchOS — Digital Crown controlled

struct VideoScrubberView: View {
    @Binding var currentTime: Double
    let duration: Double
    let bufferProgress: Double
    let onSeek: (Double) -> Void
    @State private var isDragging = false
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track background
                Rectangle()
                    .fill(Color.white.opacity(0.2))
                    .frame(height: 4)
                    .cornerRadius(2)
                
                // Buffer progress
                Rectangle()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: geo.size.width * CGFloat(min(bufferProgress, 1.0)), height: 4)
                    .cornerRadius(2)
                
                // Played progress
                Rectangle()
                    .fill(Color.red)
                    .frame(width: geo.size.width * CGFloat(min(duration > 0 ? currentTime / duration : 0, 1.0)), height: 4)
                    .cornerRadius(2)
                
                // Thumb
                Circle()
                    .fill(Color.white)
                    .frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.4), radius: 2)
                    .offset(x: geo.size.width * CGFloat(min(duration > 0 ? currentTime / duration : 0, 1.0)) - 6)
            }
        }
        .frame(height: 12)
    }
}

// MARK: - Quality Picker Sheet

struct QualityPickerSheet: View {
    let qualities: [VideoStream]
    let current: String
    let onSelect: (VideoStream) -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
                .onTapGesture { onDismiss() }
            
            VStack(spacing: 6) {
                Text("Quality")
                    .font(.headline)
                    .foregroundStyle(.white)
                
                ScrollView {
                    ForEach(qualities) { stream in
                        Button {
                            onSelect(stream)
                        } label: {
                            HStack {
                                Image(systemName: stream.quality == current ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 12))
                                    .foregroundStyle(stream.quality == current ? .blue : .white.opacity(0.5))
                                
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(stream.quality)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.white)
                                    Text(stream.format.uppercased())
                                        .font(.system(size: 9))
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                                
                                Spacer()
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(
                                stream.quality == current
                                    ? Color.blue.opacity(0.2)
                                    : Color.white.opacity(0.05)
                            )
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxHeight: 140)
            }
            .padding(12)
            .background(Color(white: 0.15))
            .cornerRadius(14)
            .padding(.horizontal, 12)
        }
    }
}