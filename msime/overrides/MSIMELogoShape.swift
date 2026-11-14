import SwiftUI
import UIKit

/// ccboard 标志：iOS 系统蓝圆角方块 + 白色双 C 弧（cc）与空格键横条（board）。
/// 与旧实现保持完全相同的公开 API（draw / strokePath / framePath / scale / 三个 Shape），
/// 键盘工具栏、皮肤选择器、欢迎页、启动页的调用点不用改；`strokeDrawn` 描线动画照旧。
enum MSIMELogo {
  static let viewBox = CGRect(x: -8, y: 0, width: 132, height: 132)
  static let frameRect = CGRect(x: -2.15686, y: 5.8335, width: 120, height: 120)
  static let frameCornerRadius: CGFloat = 26.4
  static let strokeWidth: CGFloat = 10
  static let strokeMiterLimit: CGFloat = 4
  /// 系统蓝：与 App 界面、键盘强调色同源，跟随深浅色模式。
  static let fieldColor = UIColor.systemBlue
  /// 新标志没有外框描边；保留属性供旧调用点编译，画成透明。
  static let edgeColor = UIColor.clear
  static let edgeWidth: CGFloat = 0

  static func scale(for rect: CGRect) -> CGFloat {
    min(rect.width / viewBox.width, rect.height / viewBox.height)
  }

  /// 两段 270° 的 C 弧 + 一条空格键横杠。每段之前先 move，避免 addArc 把两段连起来。
  static func strokePath(in rect: CGRect) -> CGPath {
    let point = mapper(for: rect)
    let scale = scale(for: rect)
    let radius = 18 * scale
    let path = CGMutablePath()
    for center in [CGPoint(x: 36, y: 54), CGPoint(x: 84, y: 54)] {
      let c = point(center.x, center.y)
      let start = CGPoint(x: c.x + radius * CGFloat(cos(Double.pi / 4)),
                          y: c.y + radius * CGFloat(sin(Double.pi / 4)))
      path.move(to: start)
      path.addArc(center: c, radius: radius,
                  startAngle: .pi / 4, endAngle: -.pi / 4, clockwise: true)
    }
    path.move(to: point(22, 94))
    path.addLine(to: point(98, 94))
    return path
  }

  static func framePath(in rect: CGRect) -> CGPath {
    let point = mapper(for: rect)
    let origin = point(frameRect.minX, frameRect.minY)
    let scale = scale(for: rect)
    let radius = frameCornerRadius * scale
    return CGPath(roundedRect: CGRect(x: origin.x, y: origin.y, width: frameRect.width * scale, height: frameRect.height * scale),
                  cornerWidth: radius, cornerHeight: radius, transform: nil)
  }

  /// 在当前 UIKit 图形上下文里画完整标志，供键盘工具栏和皮肤缩略图使用。
  static func draw(in rect: CGRect) {
    let scale = scale(for: rect)
    let frame = UIBezierPath(cgPath: framePath(in: rect))
    fieldColor.setFill()
    frame.fill()
    let stroke = UIBezierPath(cgPath: strokePath(in: rect))
    stroke.lineWidth = strokeWidth * scale
    stroke.lineCapStyle = .round
    stroke.lineJoinStyle = .round
    UIColor.white.setStroke()
    stroke.stroke()
  }

  private static func mapper(for rect: CGRect) -> (CGFloat, CGFloat) -> CGPoint {
    let scale = scale(for: rect)
    let originX = rect.minX + (rect.width - viewBox.width * scale) / 2 - viewBox.minX * scale
    let originY = rect.minY + (rect.height - viewBox.height * scale) / 2 - viewBox.minY * scale
    return { x, y in CGPoint(x: originX + x * scale, y: originY + y * scale) }
  }
}

/// 标志的白色图形；`strokeDrawn` 从 0 到 1 逐段描出，与启动页动画一致。
struct MSIMELogoStroke: Shape {
  func path(in rect: CGRect) -> Path { Path(MSIMELogo.strokePath(in: rect)) }
}

/// 标志的蓝色圆角外框。
struct MSIMELogoFrame: Shape {
  func path(in rect: CGRect) -> Path { Path(MSIMELogo.framePath(in: rect)) }
}

/// 完整的 ccboard 标志：系统蓝圆角方块 + 白色双 C 与空格键横条。
struct MSIMELogoMark: View {
  var strokeDrawn: CGFloat = 1

  var body: some View {
    GeometryReader { geometry in
      let scale = MSIMELogo.scale(for: CGRect(origin: .zero, size: geometry.size))
      ZStack {
        MSIMELogoFrame().fill(Color(uiColor: MSIMELogo.fieldColor))
        MSIMELogoFrame().stroke(Color(uiColor: MSIMELogo.edgeColor), lineWidth: MSIMELogo.edgeWidth * scale)
        MSIMELogoStroke()
          .trim(from: 0, to: strokeDrawn)
          .stroke(.white, style: StrokeStyle(lineWidth: MSIMELogo.strokeWidth * scale,
                                             lineCap: .round, lineJoin: .round,
                                             miterLimit: MSIMELogo.strokeMiterLimit))
      }
    }
  }
}
