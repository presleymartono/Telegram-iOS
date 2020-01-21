import Foundation
import UIKit
import AsyncDisplayKit
import Display
import TelegramCore
import SyncCore
import Postbox
import TextFormat
import UrlEscaping
import SwiftSignalKit
import AccountContext
import AvatarNode
import TelegramPresentationData

private struct PercentCounterItem: Comparable  {
    var index: Int = 0
    var percent: Int = 0
    var remainder: Int = 0
    
    static func <(lhs: PercentCounterItem, rhs: PercentCounterItem) -> Bool {
        if lhs.remainder > rhs.remainder {
            return true
        } else if lhs.remainder < rhs.remainder {
            return false
        }
        return lhs.percent < rhs.percent
    }
    
}

private func adjustPercentCount(_ items: [PercentCounterItem], left: Int) -> [PercentCounterItem] {
    var left = left
    var items = items.sorted(by: <)
    var i:Int = 0
    while i != items.count {
        let item = items[i]
        var j = i + 1
        loop: while j != items.count {
            if items[j].percent != item.percent || items[j].remainder != item.remainder {
                break loop
            }
            j += 1
        }
        if items[i].remainder == 0 {
            break
        }
        let equal = j - i
        if equal <= left {
            left -= equal
            while i != j {
                items[i].percent += 1
                i += 1
            }
        } else {
            i = j
        }
    }
    return items
}

func countNicePercent(votes: [Int], total: Int) -> [Int] {
    var result:[Int] = []
    var items:[PercentCounterItem] = []
    for _ in votes {
        result.append(0)
        items.append(PercentCounterItem())
    }
    
    let count = votes.count
    
    var left:Int = 100
    for i in 0 ..< votes.count {
        let votes = votes[i]
        items[i].index = i
        items[i].percent = Int((Float(votes) * 100) / Float(total))
        items[i].remainder = (votes * 100) - (items[i].percent * total)
        left -= items[i].percent
    }
    
    if left > 0 && left <= count {
        items = adjustPercentCount(items, left: left)
    }
    for item in items {
        result[item.index] = item.percent
    }
    
    return result
}

private final class ChatMessagePollOptionRadioNodeParameters: NSObject {
    let timestamp: Double
    let staticColor: UIColor
    let animatedColor: UIColor
    let fillColor: UIColor
    let foregroundColor: UIColor
    let offset: Double?
    let isChecked: Bool?
    let checkTransition: ChatMessagePollOptionRadioNodeCheckTransition?
    
    init(timestamp: Double, staticColor: UIColor, animatedColor: UIColor, fillColor: UIColor, foregroundColor: UIColor, offset: Double?, isChecked: Bool?, checkTransition: ChatMessagePollOptionRadioNodeCheckTransition?) {
        self.timestamp = timestamp
        self.staticColor = staticColor
        self.animatedColor = animatedColor
        self.fillColor = fillColor
        self.foregroundColor = foregroundColor
        self.offset = offset
        self.isChecked = isChecked
        self.checkTransition = checkTransition
        
        super.init()
    }
}

private final class ChatMessagePollOptionRadioNodeCheckTransition {
    let startTime: Double
    let duration: Double
    let previousValue: Bool
    let updatedValue: Bool
    
    init(startTime: Double, duration: Double, previousValue: Bool, updatedValue: Bool) {
        self.startTime = startTime
        self.duration = duration
        self.previousValue = previousValue
        self.updatedValue = updatedValue
    }
}

private final class ChatMessagePollOptionRadioNode: ASDisplayNode {
    private(set) var staticColor: UIColor?
    private(set) var animatedColor: UIColor?
    private(set) var fillColor: UIColor?
    private(set) var foregroundColor: UIColor?
    private var isInHierarchyValue: Bool = false
    private(set) var isAnimating: Bool = false
    private var startTime: Double?
    private var checkTransition: ChatMessagePollOptionRadioNodeCheckTransition?
    private(set) var isChecked: Bool?
    
    private var displayLink: ConstantDisplayLinkAnimator?
    
    private var shouldBeAnimating: Bool {
        return self.isInHierarchyValue && (self.isAnimating || self.checkTransition != nil)
    }
    
    func updateIsChecked(_ value: Bool, animated: Bool) {
        if let previousValue = self.isChecked, previousValue != value {
            self.checkTransition = ChatMessagePollOptionRadioNodeCheckTransition(startTime: CACurrentMediaTime(), duration: 0.15, previousValue: previousValue, updatedValue: value)
            self.isChecked = value
            self.updateAnimating()
            self.setNeedsDisplay()
        }
    }
    
    override init() {
        super.init()
        
        self.isUserInteractionEnabled = false
        self.isOpaque = false
    }
    
    deinit {
        self.displayLink?.isPaused = true
    }
    
    override func willEnterHierarchy() {
        super.willEnterHierarchy()
        
        let previous = self.shouldBeAnimating
        self.isInHierarchyValue = true
        let updated = self.shouldBeAnimating
        if previous != updated {
            self.updateAnimating()
        }
    }
    
    override func didExitHierarchy() {
        super.didExitHierarchy()
        
        let previous = self.shouldBeAnimating
        self.isInHierarchyValue = false
        let updated = self.shouldBeAnimating
        if previous != updated {
            self.updateAnimating()
        }
    }
    
    func update(staticColor: UIColor, animatedColor: UIColor, fillColor: UIColor, foregroundColor: UIColor, isSelectable: Bool, isAnimating: Bool) {
        var updated = false
        let shouldHaveBeenAnimating = self.shouldBeAnimating
        let wasAnimating = self.isAnimating
        if !staticColor.isEqual(self.staticColor) {
            self.staticColor = staticColor
            updated = true
        }
        if !animatedColor.isEqual(self.animatedColor) {
            self.animatedColor = animatedColor
            updated = true
        }
        if !fillColor.isEqual(self.fillColor) {
            self.fillColor = fillColor
            updated = true
        }
        if !foregroundColor.isEqual(self.foregroundColor) {
            self.foregroundColor = foregroundColor
            updated = true
        }
        if isSelectable != (self.isChecked != nil) {
            if isSelectable {
                self.isChecked = false
            } else {
                self.isChecked = nil
                self.checkTransition = nil
            }
            updated = true
        }
        if isAnimating != self.isAnimating {
            self.isAnimating = isAnimating
            let updated = self.shouldBeAnimating
            if shouldHaveBeenAnimating != updated {
                self.updateAnimating()
            }
        }
        if updated {
            self.setNeedsDisplay()
        }
    }
    
    private func updateAnimating() {
        let timestamp = CACurrentMediaTime()
        if let checkTransition = self.checkTransition {
            if checkTransition.startTime + checkTransition.duration <= timestamp {
                self.checkTransition = nil
            }
        }
        
        if self.shouldBeAnimating {
            if self.isAnimating && self.startTime == nil {
                self.startTime = timestamp
            }
            if self.displayLink == nil {
                self.displayLink = ConstantDisplayLinkAnimator(update: { [weak self] in
                    self?.updateAnimating()
                    self?.setNeedsDisplay()
                })
                self.displayLink?.isPaused = false
                self.setNeedsDisplay()
            }
        } else if let displayLink = self.displayLink {
            self.startTime = nil
            displayLink.invalidate()
            self.displayLink = nil
            self.setNeedsDisplay()
        }
    }
    
    override public func drawParameters(forAsyncLayer layer: _ASDisplayLayer) -> NSObjectProtocol? {
        if let staticColor = self.staticColor, let animatedColor = self.animatedColor, let fillColor = self.fillColor, let foregroundColor = self.foregroundColor {
            let timestamp = CACurrentMediaTime()
            var offset: Double?
            if let startTime = self.startTime {
                offset = CACurrentMediaTime() - startTime
            }
            return ChatMessagePollOptionRadioNodeParameters(timestamp: timestamp, staticColor: staticColor, animatedColor: animatedColor, fillColor: fillColor, foregroundColor: foregroundColor, offset: offset, isChecked: self.isChecked, checkTransition: self.checkTransition)
        } else {
            return nil
        }
    }
    
    @objc override public class func draw(_ bounds: CGRect, withParameters parameters: Any?, isCancelled: () -> Bool, isRasterizing: Bool) {
        if isCancelled() {
            return
        }
        
        guard let parameters = parameters as? ChatMessagePollOptionRadioNodeParameters else {
            return
        }
        
        let context = UIGraphicsGetCurrentContext()!
        
        if let offset = parameters.offset {
            let t = max(0.0, offset)
            let colorFadeInDuration = 0.2
            let color: UIColor
            if t < colorFadeInDuration {
                color = parameters.staticColor.mixedWith(parameters.animatedColor, alpha: CGFloat(t / colorFadeInDuration))
            } else {
                color = parameters.animatedColor
            }
            context.setStrokeColor(color.cgColor)
            
            let rotationDuration = 1.15
            let rotationProgress = CGFloat(offset.truncatingRemainder(dividingBy: rotationDuration) / rotationDuration)
            context.translateBy(x: bounds.midX, y: bounds.midY)
            context.rotate(by: rotationProgress * 2.0 * CGFloat.pi)
            context.translateBy(x: -bounds.midX, y: -bounds.midY)
            
            let fillDuration = 1.0
            if offset < fillDuration {
                let fillT = CGFloat(offset.truncatingRemainder(dividingBy: fillDuration) / fillDuration)
                let startAngle = fillT * 2.0 * CGFloat.pi - CGFloat.pi / 2.0
                let endAngle = -CGFloat.pi / 2.0
                
                let path = UIBezierPath(arcCenter: CGPoint(x: bounds.size.width / 2.0, y: bounds.size.height / 2.0), radius: (bounds.size.width - 1.0) / 2.0, startAngle: startAngle, endAngle: endAngle, clockwise: true)
                path.lineWidth = 1.0
                path.lineCapStyle = .round
                path.stroke()
            } else {
                let halfProgress: CGFloat = 0.7
                let fillPhase = 0.6
                let keepPhase = 0.0
                let finishPhase = 0.6
                let totalDuration = fillPhase + keepPhase + finishPhase
                let localOffset = (offset - fillDuration).truncatingRemainder(dividingBy: totalDuration)
                
                let angleOffsetT: CGFloat = -CGFloat(floor((offset - fillDuration) / totalDuration))
                let angleOffset = (angleOffsetT * (1.0 - halfProgress) * 2.0 * CGFloat.pi).truncatingRemainder(dividingBy: 2.0 * CGFloat.pi)
                context.translateBy(x: bounds.midX, y: bounds.midY)
                context.rotate(by: angleOffset)
                context.translateBy(x: -bounds.midX, y: -bounds.midY)
                
                if localOffset < fillPhase + keepPhase {
                    let fillT = CGFloat(min(1.0, localOffset / fillPhase))
                    let startAngle = -CGFloat.pi / 2.0
                    let endAngle = (fillT * halfProgress) * 2.0 * CGFloat.pi - CGFloat.pi / 2.0
                    
                    let path = UIBezierPath(arcCenter: CGPoint(x: bounds.size.width / 2.0, y: bounds.size.height / 2.0), radius: (bounds.size.width - 1.0) / 2.0, startAngle: startAngle, endAngle: endAngle, clockwise: true)
                    path.lineWidth = 1.0
                    path.lineCapStyle = .round
                    path.stroke()
                } else {
                    let finishT = CGFloat((localOffset - (fillPhase + keepPhase)) / finishPhase)
                    let endAngle = halfProgress * 2.0 * CGFloat.pi - CGFloat.pi / 2.0
                    let startAngle = -CGFloat.pi / 2.0 * (1.0 - finishT) + endAngle * finishT
                    
                    let path = UIBezierPath(arcCenter: CGPoint(x: bounds.size.width / 2.0, y: bounds.size.height / 2.0), radius: (bounds.size.width - 1.0) / 2.0, startAngle: startAngle, endAngle: endAngle, clockwise: true)
                    path.lineWidth = 1.0
                    path.lineCapStyle = .round
                    path.stroke()
                }
            }
        } else {
            if let isChecked = parameters.isChecked {
                let checkedT: CGFloat
                let fromValue: CGFloat
                let toValue: CGFloat
                let fromAlpha: CGFloat
                let toAlpha: CGFloat
                if let checkTransition = parameters.checkTransition {
                    checkedT = CGFloat(max(0.0, min(1.0, (parameters.timestamp - checkTransition.startTime) / checkTransition.duration)))
                    fromValue = checkTransition.previousValue ? bounds.width : 0.0
                    fromAlpha = checkTransition.previousValue ? 1.0 : 0.0
                    toValue = checkTransition.updatedValue ? bounds.width : 0.0
                    toAlpha = checkTransition.updatedValue ? 1.0 : 0.0
                } else {
                    checkedT = 1.0
                    fromValue = isChecked ? bounds.width : 0.0
                    fromAlpha = isChecked ? 1.0 : 0.0
                    toValue = isChecked ? bounds.width : 0.0
                    toAlpha = isChecked ? 1.0 : 0.0
                }
                
                let diameter = fromValue * (1.0 - checkedT) + toValue * checkedT
                let alpha = fromAlpha * (1.0 - checkedT) + toAlpha * checkedT
                
                if abs(diameter - 1.0) > CGFloat.ulpOfOne {
                    context.setStrokeColor(parameters.staticColor.cgColor)
                    context.strokeEllipse(in: CGRect(origin: CGPoint(x: 0.5, y: 0.5), size: CGSize(width: bounds.width - 1.0, height: bounds.height - 1.0)))
                }
                
                if !diameter.isZero {
                    context.setFillColor(parameters.fillColor.withAlphaComponent(alpha).cgColor)
                    context.fillEllipse(in: CGRect(origin: CGPoint(x: (bounds.width - diameter) / 2.0, y: (bounds.width - diameter) / 2.0), size: CGSize(width: diameter, height: diameter)))
                    
                    context.setLineWidth(1.5)
                    context.setLineJoin(.round)
                    context.setLineCap(.round)
                    
                    context.setStrokeColor(parameters.foregroundColor.withAlphaComponent(alpha).cgColor)
                    if parameters.foregroundColor.alpha.isZero {
                        context.setBlendMode(.clear)
                    }
                    let startPoint = CGPoint(x: 6.0, y: 12.13)
                    let centerPoint = CGPoint(x: 9.28, y: 15.37)
                    let endPoint = CGPoint(x: 16.0, y: 8.0)
                    
                    let pathStartT: CGFloat = 0.15
                    let pathT = max(0.0, (alpha - pathStartT) / (1.0 - pathStartT))
                    let pathMiddleT: CGFloat = 0.4
                    
                    context.move(to: startPoint)
                    if pathT >= pathMiddleT {
                        context.addLine(to: centerPoint)
                        
                        let pathEndT = (pathT - pathMiddleT) / (1.0 - pathMiddleT)
                        if pathEndT >= 1.0 {
                            context.addLine(to: endPoint)
                        } else {
                            context.addLine(to: CGPoint(x: (1.0 - pathEndT) * centerPoint.x + pathEndT * endPoint.x, y: (1.0 - pathEndT) * centerPoint.y + pathEndT * endPoint.y))
                        }
                    } else {
                        context.addLine(to: CGPoint(x: (1.0 - pathT) * startPoint.x + pathT * centerPoint.x, y: (1.0 - pathT) * startPoint.y + pathT * centerPoint.y))
                    }
                    context.strokePath()
                    context.setBlendMode(.normal)
                }
            } else {
                context.setStrokeColor(parameters.staticColor.cgColor)
                context.strokeEllipse(in: CGRect(origin: CGPoint(x: 0.5, y: 0.5), size: CGSize(width: bounds.width - 1.0, height: bounds.height - 1.0)))
            }
        }
    }
}

private let percentageFont = Font.bold(14.5)
private let percentageSmallFont = Font.bold(12.5)

private func generatePercentageImage(presentationData: ChatPresentationData, incoming: Bool, value: Int, targetValue: Int) -> UIImage {
    return generateImage(CGSize(width: 42.0, height: 20.0), rotatedContext: { size, context in
        UIGraphicsPushContext(context)
        context.clear(CGRect(origin: CGPoint(), size: size))
        let font: UIFont
        if targetValue == 100 {
            font = percentageSmallFont
        } else {
            font = percentageFont
        }
        let string = NSAttributedString(string: "\(value)%", font: font, textColor: incoming ? presentationData.theme.theme.chat.message.incoming.primaryTextColor : presentationData.theme.theme.chat.message.outgoing.primaryTextColor, paragraphAlignment: .right)
        string.draw(in: CGRect(origin: CGPoint(x: 0.0, y: targetValue == 100 ? 3.0 : 2.0), size: size))
        UIGraphicsPopContext()
    })!
}

private func generatePercentageAnimationImages(presentationData: ChatPresentationData, incoming: Bool, from fromValue: Int, to toValue: Int, duration: Double) -> [UIImage] {
    let minimumFrameDuration = 1.0 / 40.0
    let numberOfFrames = max(1, Int(duration / minimumFrameDuration))
    var images: [UIImage] = []
    for i in 0 ..< numberOfFrames {
        let t = CGFloat(i) / CGFloat(numberOfFrames)
        images.append(generatePercentageImage(presentationData: presentationData, incoming: incoming, value: Int((1.0 - t) * CGFloat(fromValue) + t * CGFloat(toValue)), targetValue: toValue))
    }
    return images
}

private struct ChatMessagePollOptionResult: Equatable {
    let normalized: CGFloat
    let percent: Int
    let count: Int32
}

private struct ChatMessagePollOptionSelection: Equatable {
    var isSelected: Bool
    var isCorrect: Bool
}

private final class ChatMessagePollOptionNode: ASDisplayNode {
    private let highlightedBackgroundNode: ASDisplayNode
    private(set) var radioNode: ChatMessagePollOptionRadioNode?
    private let percentageNode: ASDisplayNode
    private var percentageImage: UIImage?
    private var titleNode: TextNode?
    private let buttonNode: HighlightTrackingButtonNode
    private let separatorNode: ASDisplayNode
    private let resultBarNode: ASImageNode
    private let resultBarIconNode: ASImageNode
    var option: TelegramMediaPollOption?
    private(set) var currentResult: ChatMessagePollOptionResult?
    private(set) var currentSelection: ChatMessagePollOptionSelection?
    var pressed: (() -> Void)?
    var selectionUpdated: (() -> Void)?
    private var theme: PresentationTheme?
    
    override init() {
        self.highlightedBackgroundNode = ASDisplayNode()
        self.highlightedBackgroundNode.alpha = 0.0
        self.highlightedBackgroundNode.isUserInteractionEnabled = false
        
        self.buttonNode = HighlightTrackingButtonNode()
        self.separatorNode = ASDisplayNode()
        self.separatorNode.isLayerBacked = true
        
        self.resultBarNode = ASImageNode()
        self.resultBarNode.isLayerBacked = true
        self.resultBarNode.alpha = 0.0
        
        self.resultBarIconNode = ASImageNode()
        self.resultBarIconNode.isLayerBacked = true
        
        self.percentageNode = ASDisplayNode()
        self.percentageNode.alpha = 0.0
        self.percentageNode.isLayerBacked = true
        
        super.init()
        
        self.addSubnode(self.highlightedBackgroundNode)
        self.addSubnode(self.separatorNode)
        self.addSubnode(self.resultBarNode)
        self.addSubnode(self.resultBarIconNode)
        self.addSubnode(self.percentageNode)
        self.addSubnode(self.buttonNode)
        
        self.buttonNode.addTarget(self, action: #selector(self.buttonPressed), forControlEvents: .touchUpInside)
        self.buttonNode.highligthedChanged = { [weak self] highlighted in
            if let strongSelf = self {
                if highlighted {
                    strongSelf.highlightedBackgroundNode.layer.removeAnimation(forKey: "opacity")
                    strongSelf.highlightedBackgroundNode.alpha = 1.0
                } else {
                    strongSelf.highlightedBackgroundNode.alpha = 0.0
                    strongSelf.highlightedBackgroundNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.3)
                }
            }
        }
    }
    
    @objc private func buttonPressed() {
        if let radioNode = self.radioNode, let isChecked = radioNode.isChecked {
            radioNode.updateIsChecked(!isChecked, animated: true)
            self.selectionUpdated?()
        } else {
            self.pressed?()
        }
    }
    
    static func asyncLayout(_ maybeNode: ChatMessagePollOptionNode?) -> (_ accountPeerId: PeerId, _ presentationData: ChatPresentationData, _ message: Message, _ poll: TelegramMediaPoll, _ option: TelegramMediaPollOption, _ optionResult: ChatMessagePollOptionResult?, _ constrainedWidth: CGFloat) -> (minimumWidth: CGFloat, layout: ((CGFloat) -> (CGSize, (Bool, Bool) -> ChatMessagePollOptionNode))) {
        let makeTitleLayout = TextNode.asyncLayout(maybeNode?.titleNode)
        let currentResult = maybeNode?.currentResult
        let currentSelection = maybeNode?.currentSelection
        let currentTheme = maybeNode?.theme
        
        return { accountPeerId, presentationData, message, poll, option, optionResult, constrainedWidth in
            let leftInset: CGFloat = 50.0
            let rightInset: CGFloat = 12.0
            
            let incoming = message.effectivelyIncoming(accountPeerId)
            
            let (titleLayout, titleApply) = makeTitleLayout(TextNodeLayoutArguments(attributedString: NSAttributedString(string: option.text, font: presentationData.messageFont, textColor: incoming ? presentationData.theme.theme.chat.message.incoming.primaryTextColor : presentationData.theme.theme.chat.message.outgoing.primaryTextColor), backgroundColor: nil, maximumNumberOfLines: 0, truncationType: .end, constrainedSize: CGSize(width: max(1.0, constrainedWidth - leftInset - rightInset), height: CGFloat.greatestFiniteMagnitude), alignment: .left, cutout: nil, insets: UIEdgeInsets(top: 1.0, left: 0.0, bottom: 1.0, right: 0.0)))
            
            let contentHeight: CGFloat = max(46.0, titleLayout.size.height + 22.0)
            
            let shouldHaveRadioNode = optionResult == nil
            let isSelectable: Bool
            if shouldHaveRadioNode, case .poll(multipleAnswers: true) = poll.kind, !Namespaces.Message.allScheduled.contains(message.id.namespace) {
                isSelectable = true
            } else {
                isSelectable = false
            }
            
            let themeUpdated = presentationData.theme.theme !== currentTheme
            
            var updatedPercentageImage: UIImage?
            if currentResult != optionResult || themeUpdated {
                let value = optionResult?.percent ?? 0
                updatedPercentageImage = generatePercentageImage(presentationData: presentationData, incoming: incoming, value: value, targetValue: value)
            }
            
            var resultIcon: UIImage?
            var updatedResultIcon = false
            
            var selection: ChatMessagePollOptionSelection?
            if optionResult != nil {
                if let voters = poll.results.voters {
                    for voter in voters {
                        if voter.opaqueIdentifier == option.opaqueIdentifier {
                            if voter.selected || voter.isCorrect {
                                selection = ChatMessagePollOptionSelection(isSelected: voter.selected, isCorrect: voter.isCorrect)
                            }
                            break
                        }
                    }
                }
            }
            if selection != currentSelection || themeUpdated {
                updatedResultIcon = true
                if let selection = selection {
                    var isQuiz = false
                    if case .quiz = poll.kind {
                        isQuiz = true
                    }
                    resultIcon = generateImage(CGSize(width: 16.0, height: 16.0), rotatedContext: { size, context in
                        context.clear(CGRect(origin: CGPoint(), size: size))
                        var isIncorrect = false
                        let fillColor: UIColor
                        if selection.isSelected {
                            if isQuiz {
                                if selection.isCorrect {
                                    fillColor = incoming ? presentationData.theme.theme.chat.message.incoming.polls.barPositive : presentationData.theme.theme.chat.message.outgoing.polls.barPositive
                                } else {
                                    fillColor = incoming ? presentationData.theme.theme.chat.message.incoming.polls.barNegative : presentationData.theme.theme.chat.message.outgoing.polls.barNegative
                                    isIncorrect = true
                                }
                            } else {
                                fillColor = incoming ? presentationData.theme.theme.chat.message.incoming.polls.bar : presentationData.theme.theme.chat.message.outgoing.polls.bar
                            }
                        } else if isQuiz && selection.isCorrect {
                            fillColor = incoming ? presentationData.theme.theme.chat.message.incoming.polls.bar : presentationData.theme.theme.chat.message.outgoing.polls.bar
                        } else {
                            fillColor = incoming ? presentationData.theme.theme.chat.message.incoming.polls.bar : presentationData.theme.theme.chat.message.outgoing.polls.bar
                        }
                        context.setFillColor(fillColor.cgColor)
                        context.fillEllipse(in: CGRect(origin: CGPoint(), size: size))
                        
                        let strokeColor = incoming ? presentationData.theme.theme.chat.message.incoming.polls.barIconForeground : presentationData.theme.theme.chat.message.outgoing.polls.barIconForeground
                        if strokeColor.alpha.isZero {
                            context.setBlendMode(.copy)
                        }
                        context.setStrokeColor(strokeColor.cgColor)
                        context.setLineWidth(1.5)
                        context.setLineJoin(.round)
                        context.setLineCap(.round)
                        if isIncorrect {
                            context.translateBy(x: 5.0, y: 5.0)
                            context.move(to: CGPoint(x: 0.0, y: 6.0))
                            context.addLine(to: CGPoint(x: 6.0, y: 0.0))
                            context.strokePath()
                            context.move(to: CGPoint(x: 0.0, y: 0.0))
                            context.addLine(to: CGPoint(x: 6.0, y: 6.0))
                            context.strokePath()
                        } else {
                            let _ = try? drawSvgPath(context, path: "M4,8.5 L6.44778395,10.9477839 C6.47662208,10.9766221 6.52452135,10.9754786 6.54754782,10.9524522 L12,5.5 S ")
                        }
                    })
                }
            }
            
            return (titleLayout.size.width + leftInset + rightInset, { width in
                return (CGSize(width: width, height: contentHeight), { animated, inProgress in
                    let node: ChatMessagePollOptionNode
                    if let maybeNode = maybeNode {
                        node = maybeNode
                    } else {
                        node = ChatMessagePollOptionNode()
                    }
                    
                    node.option = option
                    let previousResult = node.currentResult
                    node.currentResult = optionResult
                    node.currentSelection = selection
                    node.theme = presentationData.theme.theme
                    
                    node.highlightedBackgroundNode.backgroundColor = incoming ? presentationData.theme.theme.chat.message.incoming.polls.highlight : presentationData.theme.theme.chat.message.outgoing.polls.highlight
                    
                    node.buttonNode.accessibilityLabel = option.text
                    
                    let titleNode = titleApply()
                    if node.titleNode !== titleNode {
                        node.titleNode = titleNode
                        node.addSubnode(titleNode)
                        titleNode.isUserInteractionEnabled = false
                    }
                    if titleLayout.hasRTL {
                        titleNode.frame = CGRect(origin: CGPoint(x: width - rightInset - titleLayout.size.width, y: 11.0), size: titleLayout.size)
                    } else {
                        titleNode.frame = CGRect(origin: CGPoint(x: leftInset, y: 11.0), size: titleLayout.size)
                    }
                    
                    if shouldHaveRadioNode {
                        let radioNode: ChatMessagePollOptionRadioNode
                        if let current = node.radioNode {
                            radioNode = current
                        } else {
                            radioNode = ChatMessagePollOptionRadioNode()
                            node.addSubnode(radioNode)
                            node.radioNode = radioNode
                            if animated {
                                radioNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.25)
                            }
                        }
                        let radioSize: CGFloat = 22.0
                        radioNode.frame = CGRect(origin: CGPoint(x: 12.0, y: 12.0), size: CGSize(width: radioSize, height: radioSize))
                        radioNode.update(staticColor: incoming ? presentationData.theme.theme.chat.message.incoming.polls.radioButton : presentationData.theme.theme.chat.message.outgoing.polls.radioButton, animatedColor: incoming ? presentationData.theme.theme.chat.message.incoming.polls.radioProgress : presentationData.theme.theme.chat.message.outgoing.polls.radioProgress, fillColor: incoming ? presentationData.theme.theme.chat.message.incoming.polls.bar : presentationData.theme.theme.chat.message.outgoing.polls.bar, foregroundColor: incoming ? presentationData.theme.theme.chat.message.incoming.polls.barIconForeground : presentationData.theme.theme.chat.message.outgoing.polls.barIconForeground, isSelectable: isSelectable, isAnimating: inProgress)
                    } else if let radioNode = node.radioNode {
                        node.radioNode = nil
                        if animated {
                            radioNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.25, removeOnCompletion: false, completion: { [weak radioNode] _ in
                                radioNode?.removeFromSupernode()
                            })
                        } else {
                            radioNode.removeFromSupernode()
                        }
                    }
                    
                    if let updatedPercentageImage = updatedPercentageImage {
                        node.percentageNode.contents = updatedPercentageImage.cgImage
                        node.percentageImage = updatedPercentageImage
                    }
                    if let image = node.percentageImage {
                        node.percentageNode.frame = CGRect(origin: CGPoint(x: leftInset - 7.0 - image.size.width, y: 12.0), size: image.size)
                        if animated && previousResult?.percent != optionResult?.percent {
                            let percentageDuration = 0.27
                            let images = generatePercentageAnimationImages(presentationData: presentationData, incoming: incoming, from: previousResult?.percent ?? 0, to: optionResult?.percent ?? 0, duration: percentageDuration)
                            if !images.isEmpty {
                                let animation = CAKeyframeAnimation(keyPath: "contents")
                                animation.values = images.map { $0.cgImage! }
                                animation.duration = percentageDuration * UIView.animationDurationFactor()
                                animation.calculationMode = .discrete
                                node.percentageNode.layer.add(animation, forKey: "image")
                            }
                        }
                    }
                    
                    node.buttonNode.frame = CGRect(origin: CGPoint(x: 1.0, y: 0.0), size: CGSize(width: width - 2.0, height: contentHeight))
                    node.highlightedBackgroundNode.frame = CGRect(origin: CGPoint(x: 0.0, y: -UIScreenPixel), size: CGSize(width: width, height: contentHeight + UIScreenPixel))
                    
                    node.separatorNode.backgroundColor = incoming ? presentationData.theme.theme.chat.message.incoming.polls.separator : presentationData.theme.theme.chat.message.outgoing.polls.separator
                    node.separatorNode.frame = CGRect(origin: CGPoint(x: leftInset, y: contentHeight - UIScreenPixel), size: CGSize(width: width - leftInset, height: UIScreenPixel))
                    
                    if node.resultBarNode.image == nil || updatedResultIcon {
                        var isQuiz = false
                        if case .quiz = poll.kind {
                            isQuiz = true
                        }
                        let fillColor: UIColor
                        if let selection = selection {
                            if selection.isSelected {
                                if isQuiz {
                                    if selection.isCorrect {
                                        fillColor = incoming ? presentationData.theme.theme.chat.message.incoming.polls.barPositive : presentationData.theme.theme.chat.message.outgoing.polls.barPositive
                                    } else {
                                        fillColor = incoming ? presentationData.theme.theme.chat.message.incoming.polls.barNegative : presentationData.theme.theme.chat.message.outgoing.polls.barNegative
                                    }
                                } else {
                                    fillColor = incoming ? presentationData.theme.theme.chat.message.incoming.polls.bar : presentationData.theme.theme.chat.message.outgoing.polls.bar
                                }
                            } else if isQuiz && selection.isCorrect {
                                fillColor = incoming ? presentationData.theme.theme.chat.message.incoming.polls.bar : presentationData.theme.theme.chat.message.outgoing.polls.bar
                            } else {
                                fillColor = incoming ? presentationData.theme.theme.chat.message.incoming.polls.bar : presentationData.theme.theme.chat.message.outgoing.polls.bar
                            }
                        } else {
                            fillColor = incoming ? presentationData.theme.theme.chat.message.incoming.polls.bar : presentationData.theme.theme.chat.message.outgoing.polls.bar
                        }
                        
                        node.resultBarNode.image = generateStretchableFilledCircleImage(diameter: 6.0, color: fillColor)
                    }
                    
                    if updatedResultIcon {
                        node.resultBarIconNode.image = resultIcon
                    }
                    
                    let minBarWidth: CGFloat = 6.0
                    let resultBarWidth = minBarWidth + floor((width - leftInset - rightInset - minBarWidth) * (optionResult?.normalized ?? 0.0))
                    let barFrame = CGRect(origin: CGPoint(x: leftInset, y: contentHeight - 6.0 - 1.0), size: CGSize(width: resultBarWidth, height: 6.0))
                    node.resultBarNode.frame = barFrame
                    node.resultBarIconNode.frame = CGRect(origin: CGPoint(x: barFrame.minX - 6.0 - 16.0, y: barFrame.minY + floor((barFrame.height - 16.0) / 2.0)), size: CGSize(width: 16.0, height: 16.0))
                    node.resultBarNode.alpha = optionResult != nil ? 1.0 : 0.0
                    node.percentageNode.alpha = optionResult != nil ? 1.0 : 0.0
                    node.separatorNode.alpha = optionResult == nil ? 1.0 : 0.0
                    node.resultBarIconNode.alpha = optionResult != nil ? 1.0 : 0.0
                    if animated, currentResult != optionResult {
                        if (currentResult != nil) != (optionResult != nil) {
                            if optionResult != nil {
                                node.resultBarNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.1)
                                node.percentageNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
                                node.separatorNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.08)
                                node.resultBarIconNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
                            } else {
                                node.resultBarNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.4)
                                node.percentageNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2)
                                node.separatorNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
                                node.resultBarIconNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2)
                            }
                        }
                        
                        node.buttonNode.isAccessibilityElement = shouldHaveRadioNode
                        
                        let previousResultBarWidth = minBarWidth + floor((width - leftInset - rightInset - minBarWidth) * (currentResult?.normalized ?? 0.0))
                        let previousFrame = CGRect(origin: CGPoint(x: leftInset, y: contentHeight - 6.0 - 1.0), size: CGSize(width: previousResultBarWidth, height: 6.0))
                        
                        node.resultBarNode.layer.animateSpring(from: NSValue(cgPoint: previousFrame.center), to: NSValue(cgPoint: node.resultBarNode.frame.center), keyPath: "position", duration: 0.6, damping: 110.0)
                        node.resultBarNode.layer.animateSpring(from: NSValue(cgRect: CGRect(origin: CGPoint(), size: previousFrame.size)), to: NSValue(cgRect: CGRect(origin: CGPoint(), size: node.resultBarNode.frame.size)), keyPath: "bounds", duration: 0.6, damping: 110.0)
                    }
                    
                    return node
                })
            })
        }
    }
}

private let labelsFont = Font.regular(14.0)

class ChatMessagePollBubbleContentNode: ChatMessageBubbleContentNode {
    private let textNode: TextNode
    private let typeNode: TextNode
    private let avatarsNode: MergedAvatarsNode
    private let votersNode: TextNode
    private let buttonSubmitInactiveTextNode: TextNode
    private let buttonSubmitActiveTextNode: TextNode
    private let buttonViewResultsTextNode: TextNode
    private let buttonNode: HighlightableButtonNode
    private let statusNode: ChatMessageDateAndStatusNode
    private var optionNodes: [ChatMessagePollOptionNode] = []
    
    private var poll: TelegramMediaPoll?
    
    required init() {
        self.textNode = TextNode()
        self.textNode.isUserInteractionEnabled = false
        self.textNode.contentMode = .topLeft
        self.textNode.contentsScale = UIScreenScale
        self.textNode.displaysAsynchronously = true
        
        self.typeNode = TextNode()
        self.typeNode.isUserInteractionEnabled = false
        self.typeNode.contentMode = .topLeft
        self.typeNode.contentsScale = UIScreenScale
        self.typeNode.displaysAsynchronously = true
        
        self.avatarsNode = MergedAvatarsNode()
        
        self.votersNode = TextNode()
        self.votersNode.isUserInteractionEnabled = false
        self.votersNode.contentMode = .topLeft
        self.votersNode.contentsScale = UIScreenScale
        self.votersNode.displaysAsynchronously = true
        
        self.buttonSubmitInactiveTextNode = TextNode()
        self.buttonSubmitInactiveTextNode.isUserInteractionEnabled = false
        self.buttonSubmitInactiveTextNode.contentMode = .topLeft
        self.buttonSubmitInactiveTextNode.contentsScale = UIScreenScale
        self.buttonSubmitInactiveTextNode.displaysAsynchronously = true
        
        self.buttonSubmitActiveTextNode = TextNode()
        self.buttonSubmitActiveTextNode.isUserInteractionEnabled = false
        self.buttonSubmitActiveTextNode.contentMode = .topLeft
        self.buttonSubmitActiveTextNode.contentsScale = UIScreenScale
        self.buttonSubmitActiveTextNode.displaysAsynchronously = true
        
        self.buttonViewResultsTextNode = TextNode()
        self.buttonViewResultsTextNode.isUserInteractionEnabled = false
        self.buttonViewResultsTextNode.contentMode = .topLeft
        self.buttonViewResultsTextNode.contentsScale = UIScreenScale
        self.buttonViewResultsTextNode.displaysAsynchronously = true
        
        self.buttonNode = HighlightableButtonNode()
        
        self.statusNode = ChatMessageDateAndStatusNode()
        
        super.init()
        
        self.addSubnode(self.textNode)
        self.addSubnode(self.typeNode)
        self.addSubnode(self.avatarsNode)
        self.addSubnode(self.votersNode)
        self.addSubnode(self.buttonSubmitInactiveTextNode)
        self.addSubnode(self.buttonSubmitActiveTextNode)
        self.addSubnode(self.buttonViewResultsTextNode)
        self.addSubnode(self.buttonNode)
        
        self.buttonNode.addTarget(self, action: #selector(self.buttonPressed), forControlEvents: .touchUpInside)
        self.buttonNode.highligthedChanged = { [weak self] highlighted in
            if let strongSelf = self {
                if highlighted {
                    strongSelf.buttonSubmitActiveTextNode.layer.removeAnimation(forKey: "opacity")
                    strongSelf.buttonSubmitActiveTextNode.alpha = 0.6
                    strongSelf.buttonViewResultsTextNode.layer.removeAnimation(forKey: "opacity")
                    strongSelf.buttonViewResultsTextNode.alpha = 0.6
                } else {
                    strongSelf.buttonSubmitActiveTextNode.alpha = 1.0
                    strongSelf.buttonSubmitActiveTextNode.layer.animateAlpha(from: 0.6, to: 1.0, duration: 0.3)
                    strongSelf.buttonViewResultsTextNode.alpha = 1.0
                    strongSelf.buttonViewResultsTextNode.layer.animateAlpha(from: 0.6, to: 1.0, duration: 0.3)
                }
            }
        }
        
        self.avatarsNode.pressed = { [weak self] in
            self?.buttonPressed()
        }
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func buttonPressed() {
        guard let item = self.item, let poll = self.poll, let pollId = poll.id else {
            return
        }
        
        var hasSelection = false
        var selectedOpaqueIdentifiers: [Data] = []
        for optionNode in self.optionNodes {
            if let option = optionNode.option {
                if let isChecked = optionNode.radioNode?.isChecked {
                    hasSelection = true
                    if isChecked {
                        selectedOpaqueIdentifiers.append(option.opaqueIdentifier)
                    }
                }
            }
        }
        if !hasSelection {
            if !Namespaces.Message.allScheduled.contains(item.message.id.namespace) {
                item.controllerInteraction.requestOpenMessagePollResults(item.message.id, pollId)
            }
        } else if !selectedOpaqueIdentifiers.isEmpty {
            item.controllerInteraction.requestSelectMessagePollOptions(item.message.id, selectedOpaqueIdentifiers)
        }
    }
    
    override func asyncLayoutContent() -> (_ item: ChatMessageBubbleContentItem, _ layoutConstants: ChatMessageItemLayoutConstants, _ preparePosition: ChatMessageBubblePreparePosition, _ messageSelection: Bool?, _ constrainedSize: CGSize) -> (ChatMessageBubbleContentProperties, CGSize?, CGFloat, (CGSize, ChatMessageBubbleContentPosition) -> (CGFloat, (CGFloat) -> (CGSize, (ListViewItemUpdateAnimation, Bool) -> Void))) {
        let makeTextLayout = TextNode.asyncLayout(self.textNode)
        let makeTypeLayout = TextNode.asyncLayout(self.typeNode)
        let makeVotersLayout = TextNode.asyncLayout(self.votersNode)
        let makeSubmitInactiveTextLayout = TextNode.asyncLayout(self.buttonSubmitInactiveTextNode)
        let makeSubmitActiveTextLayout = TextNode.asyncLayout(self.buttonSubmitActiveTextNode)
        let makeViewResultsTextLayout = TextNode.asyncLayout(self.buttonViewResultsTextNode)
        let statusLayout = self.statusNode.asyncLayout()
        
        var previousPoll: TelegramMediaPoll?
        if let item = self.item {
            for media in item.message.media {
                if let media = media as? TelegramMediaPoll {
                    previousPoll = media
                }
            }
        }
        
        var previousOptionNodeLayouts: [Data: (_ accountPeerId: PeerId, _ presentationData: ChatPresentationData, _ message: Message, _ poll: TelegramMediaPoll, _ option: TelegramMediaPollOption, _ optionResult: ChatMessagePollOptionResult?, _ constrainedWidth: CGFloat) -> (minimumWidth: CGFloat, layout: ((CGFloat) -> (CGSize, (Bool, Bool) -> ChatMessagePollOptionNode)))] = [:]
        var hasSelectedOptions = false
        for optionNode in self.optionNodes {
            if let option = optionNode.option {
                previousOptionNodeLayouts[option.opaqueIdentifier] = ChatMessagePollOptionNode.asyncLayout(optionNode)
            }
            if let isChecked = optionNode.radioNode?.isChecked, isChecked {
                hasSelectedOptions = true
            }
        }
        
        return { item, layoutConstants, _, _, _ in
            let contentProperties = ChatMessageBubbleContentProperties(hidesSimpleAuthorHeader: false, headerSpacing: 0.0, hidesBackground: .never, forceFullCorners: false, forceAlignment: .none)
            
            return (contentProperties, nil, CGFloat.greatestFiniteMagnitude, { constrainedSize, position in
                let message = item.message
                
                let incoming = item.message.effectivelyIncoming(item.context.account.peerId)
                
                let horizontalInset = layoutConstants.text.bubbleInsets.left + layoutConstants.text.bubbleInsets.right
                let textConstrainedSize = CGSize(width: constrainedSize.width - horizontalInset, height: constrainedSize.height)
                
                var edited = false
                if item.attributes.updatingMedia != nil {
                    edited = true
                }
                var viewCount: Int?
                for attribute in item.message.attributes {
                    if let attribute = attribute as? EditedMessageAttribute {
                        edited = !attribute.isHidden
                    } else if let attribute = attribute as? ViewCountMessageAttribute {
                        viewCount = attribute.count
                    }
                }
                
                var dateReactions: [MessageReaction] = []
                var dateReactionCount = 0
                if let reactionsAttribute = mergedMessageReactions(attributes: item.message.attributes), !reactionsAttribute.reactions.isEmpty {
                    for reaction in reactionsAttribute.reactions {
                        if reaction.isSelected {
                            dateReactions.insert(reaction, at: 0)
                        } else {
                            dateReactions.append(reaction)
                        }
                        dateReactionCount += Int(reaction.count)
                    }
                }
                
                let dateText = stringForMessageTimestampStatus(accountPeerId: item.context.account.peerId, message: item.message, dateTimeFormat: item.presentationData.dateTimeFormat, nameDisplayOrder: item.presentationData.nameDisplayOrder, strings: item.presentationData.strings, reactionCount: dateReactionCount)
                
                let statusType: ChatMessageDateAndStatusType?
                switch position {
                    case .linear(_, .None):
                        if incoming {
                            statusType = .BubbleIncoming
                        } else {
                            if message.flags.contains(.Failed) {
                                statusType = .BubbleOutgoing(.Failed)
                            } else if (message.flags.isSending && !message.isSentOrAcknowledged) || item.attributes.updatingMedia != nil {
                                statusType = .BubbleOutgoing(.Sending)
                            } else {
                                statusType = .BubbleOutgoing(.Sent(read: item.read))
                            }
                        }
                    default:
                        statusType = nil
                }
                
                var statusSize: CGSize?
                var statusApply: ((Bool) -> Void)?
                
                if let statusType = statusType {
                    let (size, apply) = statusLayout(item.context, item.presentationData, edited, viewCount, dateText, statusType, textConstrainedSize, dateReactions)
                    statusSize = size
                    statusApply = apply
                }
                
                var poll: TelegramMediaPoll?
                for media in item.message.media {
                    if let media = media as? TelegramMediaPoll {
                        poll = media
                        break
                    }
                }

                let messageTheme = incoming ? item.presentationData.theme.theme.chat.message.incoming : item.presentationData.theme.theme.chat.message.outgoing
                
                let attributedText = NSAttributedString(string: poll?.text ?? "", font: item.presentationData.messageBoldFont, textColor: messageTheme.primaryTextColor)
                
                let textInsets = UIEdgeInsets(top: 2.0, left: 0.0, bottom: 5.0, right: 0.0)
                
                let (textLayout, textApply) = makeTextLayout(TextNodeLayoutArguments(attributedString: attributedText, backgroundColor: nil, maximumNumberOfLines: 0, truncationType: .end, constrainedSize: textConstrainedSize, alignment: .natural, cutout: nil, insets: textInsets))
                let typeText: String
                
                var avatarPeers: [Peer] = []
                if let poll = poll {
                    for peerId in poll.results.recentVoters {
                        if let peer = item.message.peers[peerId] {
                            avatarPeers.append(peer)
                        }
                    }
                }
                
                if let poll = poll, poll.isClosed {
                    typeText = item.presentationData.strings.MessagePoll_LabelClosed
                } else if let poll = poll {
                    switch poll.kind {
                    case .poll:
                        switch poll.publicity {
                        case .anonymous:
                            typeText = item.presentationData.strings.MessagePoll_LabelAnonymous
                        case .public:
                            typeText = item.presentationData.strings.MessagePoll_LabelPoll
                        }
                    case .quiz:
                        switch poll.publicity {
                        case .anonymous:
                            typeText = item.presentationData.strings.MessagePoll_LabelAnonymousQuiz
                        case .public:
                            typeText = item.presentationData.strings.MessagePoll_LabelQuiz
                        }
                    }
                } else {
                    typeText = item.presentationData.strings.MessagePoll_LabelAnonymous
                }
                let (typeLayout, typeApply) = makeTypeLayout(TextNodeLayoutArguments(attributedString: NSAttributedString(string: typeText, font: labelsFont, textColor: messageTheme.secondaryTextColor), backgroundColor: nil, maximumNumberOfLines: 0, truncationType: .end, constrainedSize: textConstrainedSize, alignment: .natural, cutout: nil, insets: UIEdgeInsets()))
                
                let votersString: String
                if let poll = poll, let totalVoters = poll.results.totalVoters {
                    switch poll.kind {
                    case .poll:
                        if totalVoters == 0 {
                            votersString = item.presentationData.strings.MessagePoll_NoVotes
                        } else {
                            votersString = item.presentationData.strings.MessagePoll_VotedCount(totalVoters)
                        }
                    case .quiz:
                        if totalVoters == 0 {
                            votersString = item.presentationData.strings.MessagePoll_QuizNoUsers
                        } else {
                            votersString = item.presentationData.strings.MessagePoll_QuizCount(totalVoters)
                        }
                    }
                } else {
                    votersString = " "
                }
                let (votersLayout, votersApply) = makeVotersLayout(TextNodeLayoutArguments(attributedString: NSAttributedString(string: votersString, font: labelsFont, textColor: messageTheme.secondaryTextColor), backgroundColor: nil, maximumNumberOfLines: 0, truncationType: .end, constrainedSize: textConstrainedSize, alignment: .natural, cutout: nil, insets: textInsets))
                
                let (buttonSubmitInactiveTextLayout, buttonSubmitInactiveTextApply) = makeSubmitInactiveTextLayout(TextNodeLayoutArguments(attributedString: NSAttributedString(string: item.presentationData.strings.MessagePoll_SubmitVote, font: Font.regular(17.0), textColor: messageTheme.accentControlDisabledColor), backgroundColor: nil, maximumNumberOfLines: 1, truncationType: .end, constrainedSize: textConstrainedSize, alignment: .natural, cutout: nil, insets: textInsets))
                let (buttonSubmitActiveTextLayout, buttonSubmitActiveTextApply) = makeSubmitActiveTextLayout(TextNodeLayoutArguments(attributedString: NSAttributedString(string: item.presentationData.strings.MessagePoll_SubmitVote, font: Font.regular(17.0), textColor: messageTheme.polls.bar), backgroundColor: nil, maximumNumberOfLines: 1, truncationType: .end, constrainedSize: textConstrainedSize, alignment: .natural, cutout: nil, insets: textInsets))
                let (buttonViewResultsTextLayout, buttonViewResultsTextApply) = makeViewResultsTextLayout(TextNodeLayoutArguments(attributedString: NSAttributedString(string: item.presentationData.strings.MessagePoll_ViewResults, font: Font.regular(17.0), textColor: messageTheme.polls.bar), backgroundColor: nil, maximumNumberOfLines: 1, truncationType: .end, constrainedSize: textConstrainedSize, alignment: .natural, cutout: nil, insets: textInsets))
                
                var textFrame = CGRect(origin: CGPoint(x: -textInsets.left, y: -textInsets.top), size: textLayout.size)
                var textFrameWithoutInsets = CGRect(origin: CGPoint(x: textFrame.origin.x + textInsets.left, y: textFrame.origin.y + textInsets.top), size: CGSize(width: textFrame.width - textInsets.left - textInsets.right, height: textFrame.height - textInsets.top - textInsets.bottom))
                
                var statusFrame: CGRect?
                if let statusSize = statusSize {
                    statusFrame = CGRect(origin: CGPoint(x: textFrameWithoutInsets.maxX - statusSize.width, y: textFrameWithoutInsets.maxY - statusSize.height), size: statusSize)
                }
                
                textFrame = textFrame.offsetBy(dx: layoutConstants.text.bubbleInsets.left, dy: layoutConstants.text.bubbleInsets.top)
                textFrameWithoutInsets = textFrameWithoutInsets.offsetBy(dx: layoutConstants.text.bubbleInsets.left, dy: layoutConstants.text.bubbleInsets.top)
                statusFrame = statusFrame?.offsetBy(dx: layoutConstants.text.bubbleInsets.left, dy: layoutConstants.text.bubbleInsets.top)
                
                var boundingSize: CGSize = textFrameWithoutInsets.size
                boundingSize.width = max(boundingSize.width, typeLayout.size.width)
                boundingSize.width = max(boundingSize.width, votersLayout.size.width + 4.0 + (statusSize?.width ?? 0.0))
                boundingSize.width = max(boundingSize.width, buttonSubmitInactiveTextLayout.size.width + 4.0 + (statusSize?.width ?? 0.0))
                boundingSize.width = max(boundingSize.width, buttonViewResultsTextLayout.size.width + 4.0 + (statusSize?.width ?? 0.0))
                
                boundingSize.width += layoutConstants.text.bubbleInsets.left + layoutConstants.text.bubbleInsets.right
                boundingSize.height += layoutConstants.text.bubbleInsets.top + layoutConstants.text.bubbleInsets.bottom
                
                var pollOptionsFinalizeLayouts: [(CGFloat) -> (CGSize, (Bool, Bool) -> ChatMessagePollOptionNode)] = []
                if let poll = poll {
                    var optionVoterCount: [Int: Int32] = [:]
                    var maxOptionVoterCount: Int32 = 0
                    var totalVoterCount: Int32 = 0
                    let voters: [TelegramMediaPollOptionVoters]?
                    if poll.isClosed {
                        voters = poll.results.voters ?? []
                    } else {
                        voters = poll.results.voters
                    }
                    if let voters = voters, let totalVoters = poll.results.totalVoters {
                        var didVote = false
                        for voter in voters {
                            if voter.selected {
                                didVote = true
                            }
                        }
                        totalVoterCount = totalVoters
                        if didVote || poll.isClosed {
                            for i in 0 ..< poll.options.count {
                                inner: for optionVoters in voters {
                                    if optionVoters.opaqueIdentifier == poll.options[i].opaqueIdentifier {
                                        optionVoterCount[i] = optionVoters.count
                                        maxOptionVoterCount = max(maxOptionVoterCount, optionVoters.count)
                                        break inner
                                    }
                                }
                            }
                        }
                    }
                    
                    var optionVoterCounts: [Int]
                    if totalVoterCount != 0 {
                        optionVoterCounts = countNicePercent(votes: (0 ..< poll.options.count).map({ Int(optionVoterCount[$0] ?? 0) }), total: Int(totalVoterCount))
                    } else {
                        optionVoterCounts = Array(repeating: 0, count: poll.options.count)
                    }
                    
                    for i in 0 ..< poll.options.count {
                        let option = poll.options[i]
                        
                        let makeLayout: (_ accountPeerId: PeerId, _ presentationData: ChatPresentationData, _ message: Message, _ poll: TelegramMediaPoll, _ option: TelegramMediaPollOption, _ optionResult: ChatMessagePollOptionResult?, _ constrainedWidth: CGFloat) -> (minimumWidth: CGFloat, layout: ((CGFloat) -> (CGSize, (Bool, Bool) -> ChatMessagePollOptionNode)))
                        if let previous = previousOptionNodeLayouts[option.opaqueIdentifier] {
                            makeLayout = previous
                        } else {
                            makeLayout = ChatMessagePollOptionNode.asyncLayout(nil)
                        }
                        var optionResult: ChatMessagePollOptionResult?
                        if let count = optionVoterCount[i] {
                            if maxOptionVoterCount != 0 && totalVoterCount != 0 {
                                optionResult = ChatMessagePollOptionResult(normalized: CGFloat(count) / CGFloat(maxOptionVoterCount), percent: optionVoterCounts[i], count: count)
                            } else if poll.isClosed {
                                optionResult = ChatMessagePollOptionResult(normalized: 0, percent: 0, count: 0)
                            }
                        } else if poll.isClosed {
                            optionResult = ChatMessagePollOptionResult(normalized: 0, percent: 0, count: 0)
                        }
                        let result = makeLayout(item.context.account.peerId, item.presentationData, item.message, poll, option, optionResult, constrainedSize.width - layoutConstants.bubble.borderInset * 2.0)
                        boundingSize.width = max(boundingSize.width, result.minimumWidth + layoutConstants.bubble.borderInset * 2.0)
                        pollOptionsFinalizeLayouts.append(result.1)
                    }
                }
                
                boundingSize.width = max(boundingSize.width, min(270.0, constrainedSize.width))
                
                var canVote = false
                if (item.message.id.namespace == Namespaces.Message.Cloud || Namespaces.Message.allScheduled.contains(item.message.id.namespace)), let poll = poll, poll.pollId.namespace == Namespaces.Media.CloudPoll, !poll.isClosed {
                    var hasVoted = false
                    if let voters = poll.results.voters {
                        for voter in voters {
                            if voter.selected {
                                hasVoted = true
                                break
                            }
                        }
                    }
                    if !hasVoted {
                        canVote = true
                    }
                }
                
                return (boundingSize.width, { boundingWidth in
                    var resultSize = CGSize(width: max(boundingSize.width, boundingWidth), height: boundingSize.height)
                    
                    let titleTypeSpacing: CGFloat = -4.0
                    let typeOptionsSpacing: CGFloat = 3.0
                    resultSize.height += titleTypeSpacing + typeLayout.size.height + typeOptionsSpacing
                    
                    var optionNodesSizesAndApply: [(CGSize, (Bool, Bool) -> ChatMessagePollOptionNode)] = []
                    for finalizeLayout in pollOptionsFinalizeLayouts {
                        let result = finalizeLayout(boundingWidth - layoutConstants.bubble.borderInset * 2.0)
                        resultSize.width = max(resultSize.width, result.0.width + layoutConstants.bubble.borderInset * 2.0)
                        resultSize.height += result.0.height
                        optionNodesSizesAndApply.append(result)
                    }
                    
                    let optionsVotersSpacing: CGFloat = 11.0
                    let optionsButtonSpacing: CGFloat = 9.0
                    let votersBottomSpacing: CGFloat = 11.0
                    resultSize.height += optionsVotersSpacing + votersLayout.size.height + votersBottomSpacing
                    
                    let buttonSubmitInactiveTextFrame = CGRect(origin: CGPoint(x: floor((resultSize.width - buttonSubmitInactiveTextLayout.size.width) / 2.0), y: optionsButtonSpacing), size: buttonSubmitInactiveTextLayout.size)
                    let buttonSubmitActiveTextFrame = CGRect(origin: CGPoint(x: floor((resultSize.width - buttonSubmitActiveTextLayout.size.width) / 2.0), y: optionsButtonSpacing), size: buttonSubmitActiveTextLayout.size)
                    let buttonViewResultsTextFrame = CGRect(origin: CGPoint(x: floor((resultSize.width - buttonViewResultsTextLayout.size.width) / 2.0), y: optionsButtonSpacing), size: buttonViewResultsTextLayout.size)
                    
                    var adjustedStatusFrame: CGRect?
                    if let statusFrame = statusFrame {
                        var localStatusFrame = CGRect(origin: CGPoint(x: boundingWidth - statusFrame.size.width - layoutConstants.text.bubbleInsets.right, y: resultSize.height - statusFrame.size.height - 6.0), size: statusFrame.size)
                        if localStatusFrame.minX <= buttonViewResultsTextFrame.maxX || localStatusFrame.minX <= buttonSubmitActiveTextFrame.maxX {
                            localStatusFrame.origin.y += 10.0
                            resultSize.height += 10.0
                        }
                        adjustedStatusFrame = localStatusFrame
                    }
                    
                    return (resultSize, { [weak self] animation, synchronousLoad in
                        if let strongSelf = self {
                            strongSelf.item = item
                            strongSelf.poll = poll
                            
                            let cachedLayout = strongSelf.textNode.cachedLayout
                            
                            if case .System = animation {
                                if let cachedLayout = cachedLayout {
                                    if cachedLayout != textLayout {
                                        if let textContents = strongSelf.textNode.contents {
                                            let fadeNode = ASDisplayNode()
                                            fadeNode.displaysAsynchronously = false
                                            fadeNode.contents = textContents
                                            fadeNode.frame = strongSelf.textNode.frame
                                            fadeNode.isLayerBacked = true
                                            strongSelf.addSubnode(fadeNode)
                                            fadeNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false, completion: { [weak fadeNode] _ in
                                                fadeNode?.removeFromSupernode()
                                            })
                                            strongSelf.textNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.15)
                                        }
                                    }
                                }
                            }
                            
                            let _ = textApply()
                            let _ = typeApply()
                            
                            var verticalOffset = textFrame.maxY + titleTypeSpacing + typeLayout.size.height + typeOptionsSpacing
                            var updatedOptionNodes: [ChatMessagePollOptionNode] = []
                            for i in 0 ..< optionNodesSizesAndApply.count {
                                let (size, apply) = optionNodesSizesAndApply[i]
                                var isRequesting = false
                                if let poll = poll, i < poll.options.count {
                                    if let inProgressOpaqueIds = item.controllerInteraction.pollActionState.pollMessageIdsInProgress[item.message.id] {
                                        isRequesting = inProgressOpaqueIds.contains(poll.options[i].opaqueIdentifier)
                                    }
                                }
                                let optionNode = apply(animation.isAnimated, isRequesting)
                                if optionNode.supernode !== strongSelf {
                                    strongSelf.addSubnode(optionNode)
                                    let option = optionNode.option
                                    optionNode.pressed = {
                                        guard let strongSelf = self, let item = strongSelf.item, let option = option else {
                                            return
                                        }
                                        
                                        item.controllerInteraction.requestSelectMessagePollOptions(item.message.id, [option.opaqueIdentifier])
                                    }
                                    optionNode.selectionUpdated = {
                                        guard let strongSelf = self else {
                                            return
                                        }
                                        strongSelf.updateSelection()
                                    }
                                }
                                optionNode.frame = CGRect(origin: CGPoint(x: layoutConstants.bubble.borderInset, y: verticalOffset), size: size)
                                verticalOffset += size.height
                                updatedOptionNodes.append(optionNode)
                                optionNode.isUserInteractionEnabled = canVote && item.controllerInteraction.pollActionState.pollMessageIdsInProgress[item.message.id] == nil
                            }
                            for optionNode in strongSelf.optionNodes {
                                if !updatedOptionNodes.contains(where: { $0 === optionNode }) {
                                    optionNode.removeFromSupernode()
                                }
                            }
                            strongSelf.optionNodes = updatedOptionNodes
                            
                            if let statusApply = statusApply, let adjustedStatusFrame = adjustedStatusFrame {
                                let previousStatusFrame = strongSelf.statusNode.frame
                                strongSelf.statusNode.frame = adjustedStatusFrame
                                var hasAnimation = true
                                if case .None = animation {
                                    hasAnimation = false
                                }
                                statusApply(hasAnimation)
                                if strongSelf.statusNode.supernode == nil {
                                    strongSelf.addSubnode(strongSelf.statusNode)
                                } else {
                                    if case let .System(duration) = animation {
                                        let delta = CGPoint(x: previousStatusFrame.maxX - adjustedStatusFrame.maxX, y: previousStatusFrame.minY - adjustedStatusFrame.minY)
                                        let statusPosition = strongSelf.statusNode.layer.position
                                        let previousPosition = CGPoint(x: statusPosition.x + delta.x, y: statusPosition.y + delta.y)
                                        strongSelf.statusNode.layer.animatePosition(from: previousPosition, to: statusPosition, duration: duration, timingFunction: kCAMediaTimingFunctionSpring)
                                    }
                                }
                            } else if strongSelf.statusNode.supernode != nil {
                                strongSelf.statusNode.removeFromSupernode()
                            }
                            
                            if textLayout.hasRTL {
                                strongSelf.textNode.frame = CGRect(origin: CGPoint(x: resultSize.width - textFrame.size.width - textInsets.left - layoutConstants.text.bubbleInsets.right, y: textFrame.origin.y), size: textFrame.size)
                            } else {
                                strongSelf.textNode.frame = textFrame
                            }
                            let typeFrame = CGRect(origin: CGPoint(x: textFrame.minX, y: textFrame.maxY + titleTypeSpacing), size: typeLayout.size)
                            strongSelf.typeNode.frame = typeFrame
                            let avatarsFrame = CGRect(origin: CGPoint(x: typeFrame.maxX + 6.0, y: typeFrame.minY + floor((typeFrame.height - mergedImageSize) / 2.0)), size: CGSize(width: mergedImageSize + mergedImageSpacing * 2.0, height: mergedImageSize))
                            strongSelf.avatarsNode.frame = avatarsFrame
                            strongSelf.avatarsNode.updateLayout(size: avatarsFrame.size)
                            strongSelf.avatarsNode.update(context: item.context, peers: avatarPeers, synchronousLoad: synchronousLoad)
                            let alphaTransition: ContainedViewLayoutTransition
                            if animation.isAnimated {
                                alphaTransition = .animated(duration: 0.25, curve: .easeInOut)
                                alphaTransition.updateAlpha(node: strongSelf.avatarsNode, alpha: avatarPeers.isEmpty ? 0.0 : 1.0)
                            } else {
                                alphaTransition = .immediate
                            }
                            
                            let _ = votersApply()
                            strongSelf.votersNode.frame = CGRect(origin: CGPoint(x: floor((resultSize.width - votersLayout.size.width) / 2.0), y: verticalOffset + optionsVotersSpacing), size: votersLayout.size)
                            if animation.isAnimated, let previousPoll = previousPoll, let poll = poll {
                                if previousPoll.results.totalVoters == nil && poll.results.totalVoters != nil {
                                    strongSelf.votersNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.25)
                                }
                            }
                            
                            let _ = buttonSubmitInactiveTextApply()
                            strongSelf.buttonSubmitInactiveTextNode.frame = buttonSubmitInactiveTextFrame.offsetBy(dx: 0.0, dy: verticalOffset)
                            
                            let _ = buttonSubmitActiveTextApply()
                            strongSelf.buttonSubmitActiveTextNode.frame = buttonSubmitActiveTextFrame.offsetBy(dx: 0.0, dy: verticalOffset)
                            
                            let _ = buttonViewResultsTextApply()
                            strongSelf.buttonViewResultsTextNode.frame = buttonViewResultsTextFrame.offsetBy(dx: 0.0, dy: verticalOffset)
                            
                            strongSelf.buttonNode.frame = CGRect(origin: CGPoint(x: 0.0, y: verticalOffset), size: CGSize(width: resultSize.width, height: 44.0))
                            
                            strongSelf.updateSelection()
                        }
                    })
                })
            })
        }
    }
    
    private func updateSelection() {
        guard let item = self.item, let poll = self.poll else {
            return
        }
        
        let disableAllActions = false
        
        var hasSelection = false
        switch poll.kind {
        case .poll(true):
            hasSelection = true
        default:
            break
        }
        
        var hasSelectedOptions = false
        for optionNode in self.optionNodes {
            if let isChecked = optionNode.radioNode?.isChecked {
                if isChecked {
                    hasSelectedOptions = true
                }
            }
        }
        
        var hasResults = false
        if poll.isClosed {
            hasResults = true
            hasSelection = false
            if let totalVoters = poll.results.totalVoters, totalVoters == 0 {
                hasResults = false
            }
        } else {
            if let totalVoters = poll.results.totalVoters, totalVoters != 0 {
                if let voters = poll.results.voters {
                    for voter in voters {
                        if voter.selected {
                            hasResults = true
                            break
                        }
                    }
                }
            }
        }
        
        if !disableAllActions && hasSelection && !hasResults && poll.pollId.namespace == Namespaces.Media.CloudPoll {
            self.votersNode.isHidden = true
            self.buttonViewResultsTextNode.isHidden = true
            self.buttonSubmitInactiveTextNode.isHidden = hasSelectedOptions
            self.buttonSubmitActiveTextNode.isHidden = !hasSelectedOptions
            self.buttonNode.isHidden = !hasSelectedOptions
            self.buttonNode.isUserInteractionEnabled = true
        } else {
            if case .public = poll.publicity, hasResults, !disableAllActions {
                self.votersNode.isHidden = true
                self.buttonViewResultsTextNode.isHidden = false
                self.buttonNode.isHidden = false
                
                if Namespaces.Message.allScheduled.contains(item.message.id.namespace) {
                    self.buttonNode.isUserInteractionEnabled = false
                } else {
                    self.buttonNode.isUserInteractionEnabled = true
                }
            } else {
                self.votersNode.isHidden = false
                self.buttonViewResultsTextNode.isHidden = true
                self.buttonNode.isHidden = true
                self.buttonNode.isUserInteractionEnabled = true
            }
            self.buttonSubmitInactiveTextNode.isHidden = true
            self.buttonSubmitActiveTextNode.isHidden = true
        }
        
        self.avatarsNode.isUserInteractionEnabled = !self.buttonViewResultsTextNode.isHidden
    }
    
    override func animateInsertion(_ currentTimestamp: Double, duration: Double) {
        self.textNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
        self.statusNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
    }
    
    override func animateAdded(_ currentTimestamp: Double, duration: Double) {
        self.textNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
        self.statusNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
    }
    
    override func animateRemoved(_ currentTimestamp: Double, duration: Double) {
        self.textNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false)
        self.statusNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false)
    }
    
    override func tapActionAtPoint(_ point: CGPoint, gesture: TapLongTapOrDoubleTapGesture, isEstimating: Bool) -> ChatMessageBubbleContentTapAction {
        let textNodeFrame = self.textNode.frame
        if let (index, attributes) = self.textNode.attributesAtPoint(CGPoint(x: point.x - textNodeFrame.minX, y: point.y - textNodeFrame.minY)) {
            if let url = attributes[NSAttributedString.Key(rawValue: TelegramTextAttributes.URL)] as? String {
                var concealed = true
                if let (attributeText, fullText) = self.textNode.attributeSubstring(name: TelegramTextAttributes.URL, index: index) {
                    concealed = !doesUrlMatchText(url: url, text: attributeText, fullText: fullText)
                }
                return .url(url: url, concealed: concealed)
            } else if let peerMention = attributes[NSAttributedString.Key(rawValue: TelegramTextAttributes.PeerMention)] as? TelegramPeerMention {
                return .peerMention(peerMention.peerId, peerMention.mention)
            } else if let peerName = attributes[NSAttributedString.Key(rawValue: TelegramTextAttributes.PeerTextMention)] as? String {
                return .textMention(peerName)
            } else if let botCommand = attributes[NSAttributedString.Key(rawValue: TelegramTextAttributes.BotCommand)] as? String {
                return .botCommand(botCommand)
            } else if let hashtag = attributes[NSAttributedString.Key(rawValue: TelegramTextAttributes.Hashtag)] as? TelegramHashtag {
                return .hashtag(hashtag.peerName, hashtag.hashtag)
            } else {
                return .none
            }
        } else {
            for optionNode in self.optionNodes {
                if optionNode.frame.contains(point), case .tap = gesture {
                    if optionNode.isUserInteractionEnabled {
                        return .ignore
                    } else if let result = optionNode.currentResult, let item = self.item, !Namespaces.Message.allScheduled.contains(item.message.id.namespace), let poll = self.poll, let option = optionNode.option {
                        switch poll.publicity {
                        case .anonymous:
                            let string: String
                            switch poll.kind {
                            case .poll:
                                if result.count == 0 {
                                    string = item.presentationData.strings.MessagePoll_NoVotes
                                } else {
                                    string = item.presentationData.strings.MessagePoll_VotedCount(result.count)
                                }
                            case .quiz:
                                if result.count == 0 {
                                    string = item.presentationData.strings.MessagePoll_QuizNoUsers
                                } else {
                                    string = item.presentationData.strings.MessagePoll_QuizCount(result.count)
                                }
                            }
                            return .tooltip(string, optionNode, optionNode.bounds.offsetBy(dx: 0.0, dy: 10.0))
                        case .public:
                            var hasNonZeroVoters = false
                            if let voters = poll.results.voters {
                                for voter in voters {
                                    if voter.count != 0 {
                                        hasNonZeroVoters = true
                                        break
                                    }
                                }
                            }
                            if hasNonZeroVoters {
                                if !isEstimating {
                                    item.controllerInteraction.openMessagePollResults(item.message.id, option.opaqueIdentifier)
                                    return .ignore
                                }
                                return .openMessage
                            }
                        }
                    }
                }
            }
            if self.buttonNode.isUserInteractionEnabled, !self.buttonNode.isHidden, self.buttonNode.frame.contains(point) {
                return .ignore
            }
            if self.avatarsNode.isUserInteractionEnabled, !self.avatarsNode.isHidden, self.avatarsNode.frame.contains(point) {
                return .ignore
            }
            return .none
        }
    }
    
    override func reactionTargetNode(value: String) -> (ASDisplayNode, Int)? {
        if !self.statusNode.isHidden {
            return self.statusNode.reactionNode(value: value)
        }
        return nil
    }
}

private enum PeerAvatarReference: Equatable {
    case letters(PeerId, [String])
    case image(PeerReference, TelegramMediaImageRepresentation)
    
    var peerId: PeerId {
        switch self {
        case let .letters(value, _):
            return value
        case let .image(value, _):
            return value.id
        }
    }
}

private extension PeerAvatarReference {
    init(peer: Peer) {
        if let photo = peer.smallProfileImage, let peerReference = PeerReference(peer) {
            self = .image(peerReference, photo)
        } else {
            self = .letters(peer.id, peer.displayLetters)
        }
    }
}

private final class MergedAvatarsNodeArguments: NSObject {
    let peers: [PeerAvatarReference]
    let images: [PeerId: UIImage]
    
    init(peers: [PeerAvatarReference], images: [PeerId: UIImage]) {
        self.peers = peers
        self.images = images
    }
}

private let mergedImageSize: CGFloat = 16.0
private let mergedImageSpacing: CGFloat = 15.0

private let avatarFont = avatarPlaceholderFont(size: 8.0)

private final class MergedAvatarsNode: ASDisplayNode {
    private var peers: [PeerAvatarReference] = []
    private var images: [PeerId: UIImage] = [:]
    private var disposables: [PeerId: Disposable] = [:]
    private let buttonNode: HighlightTrackingButtonNode
    
    var pressed: (() -> Void)?
    
    override init() {
        self.buttonNode = HighlightTrackingButtonNode()
        
        super.init()
        
        self.isOpaque = false
        self.displaysAsynchronously = true
        self.buttonNode.addTarget(self, action: #selector(self.buttonPressed), forControlEvents: .touchUpInside)
        self.addSubnode(self.buttonNode)
    }
    
    deinit {
        for (_, disposable) in self.disposables {
            disposable.dispose()
        }
    }
    
    @objc private func buttonPressed() {
        self.pressed?()
    }
    
    func updateLayout(size: CGSize) {
        self.buttonNode.frame = CGRect(origin: CGPoint(), size: size)
    }
    
    func update(context: AccountContext, peers: [Peer], synchronousLoad: Bool) {
        var filteredPeers = peers.map(PeerAvatarReference.init)
        if filteredPeers.count > 3 {
            filteredPeers.dropLast(filteredPeers.count - 3)
        }
        if filteredPeers != self.peers {
            self.peers = filteredPeers
            
            var validImageIds: [PeerId] = []
            for peer in filteredPeers {
                if case .image = peer {
                    validImageIds.append(peer.peerId)
                }
            }
            
            var removedImageIds: [PeerId] = []
            for (id, _) in self.images {
                if !validImageIds.contains(id) {
                    removedImageIds.append(id)
                }
            }
            var removedDisposableIds: [PeerId] = []
            for (id, disposable) in self.disposables {
                if !validImageIds.contains(id) {
                    disposable.dispose()
                    removedDisposableIds.append(id)
                }
            }
            for id in removedImageIds {
                self.images.removeValue(forKey: id)
            }
            for id in removedDisposableIds {
                self.disposables.removeValue(forKey: id)
            }
            for peer in filteredPeers {
                switch peer {
                case let .image(peerReference, representation):
                    if self.disposables[peer.peerId] == nil {
                        if let signal = peerAvatarImage(account: context.account, peerReference: peerReference, authorOfMessage: nil, representation: representation, displayDimensions: CGSize(width: mergedImageSize, height: mergedImageSize), synchronousLoad: synchronousLoad) {
                            let disposable = (signal
                            |> deliverOnMainQueue).start(next: { [weak self] image in
                                guard let strongSelf = self else {
                                    return
                                }
                                if let image = image {
                                    strongSelf.images[peer.peerId] = image
                                    strongSelf.setNeedsDisplay()
                                }
                            })
                            self.disposables[peer.peerId] = disposable
                        }
                    }
                case .letters:
                    break
                }
            }
            self.setNeedsDisplay()
        }
    }
    
    override func drawParameters(forAsyncLayer layer: _ASDisplayLayer) -> NSObjectProtocol {
        return MergedAvatarsNodeArguments(peers: self.peers, images: self.images)
    }
    
    @objc override class func draw(_ bounds: CGRect, withParameters parameters: Any?, isCancelled: () -> Bool, isRasterizing: Bool) {
        assertNotOnMainThread()
        
        let context = UIGraphicsGetCurrentContext()!
        
        if !isRasterizing {
            context.setBlendMode(.copy)
            context.setFillColor(UIColor.clear.cgColor)
            context.fill(bounds)
        }
        
        guard let parameters = parameters as? MergedAvatarsNodeArguments else {
            return
        }
        
        let imageOverlaySpacing: CGFloat = 1.0
        context.setBlendMode(.copy)
        
        var currentX = mergedImageSize + mergedImageSpacing * CGFloat(parameters.peers.count - 1) - mergedImageSize
        for i in (0 ..< parameters.peers.count).reversed() {
            let imageRect = CGRect(origin: CGPoint(x: currentX, y: 0.0), size: CGSize(width: mergedImageSize, height: mergedImageSize))
            context.setFillColor(UIColor.clear.cgColor)
            context.fillEllipse(in: imageRect.insetBy(dx: -1.0, dy: -1.0))
            
            context.saveGState()
            switch parameters.peers[i] {
            case let .letters(peerId, letters):
                context.translateBy(x: currentX, y: 0.0)
                drawPeerAvatarLetters(context: context, size: CGSize(width: mergedImageSize, height: mergedImageSize), font: avatarFont, letters: letters, peerId: peerId)
                context.translateBy(x: -currentX, y: 0.0)
            case let .image(reference):
                if let image = parameters.images[parameters.peers[i].peerId] {
                    context.translateBy(x: imageRect.midX, y: imageRect.midY)
                    context.scaleBy(x: 1.0, y: -1.0)
                    context.translateBy(x: -imageRect.midX, y: -imageRect.midY)
                    context.draw(image.cgImage!, in: imageRect)
                } else {
                    context.setFillColor(UIColor.gray.cgColor)
                    context.fillEllipse(in: imageRect)
                }
            }
            context.restoreGState()
            currentX -= mergedImageSpacing
        }
    }
}
