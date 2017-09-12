//
//  AnyMenuViewAnimator.swift
//  AnyMenu iOS
//
//  Created by Murat Yilmaz on 06.09.17.
//  Copyright © 2017 Flinesoft. All rights reserved.
//

import UIKit

// TODO: add support for menu overlays content

internal class AnyMenuViewAnimator: NSObject {
    // MARK: - Stored Instance Properties
    fileprivate weak var viewController: AnyMenuViewController!

    fileprivate let animation: MenuAnimation

    fileprivate var initialMenuViewTransform: CGAffineTransform!
    fileprivate var finalMenuViewTransform: CGAffineTransform!

    fileprivate var initialContentViewTransform: CGAffineTransform!
    fileprivate var finalContentViewTransform: CGAffineTransform!

    fileprivate var panGestureRecognizer: UIPanGestureRecognizer?
    fileprivate var screenEdgePanGestureRecognizer: UIScreenEdgePanGestureRecognizer?
    fileprivate var tapGestureRecognizer: UITapGestureRecognizer?

    internal var gestureRecognizers: [UIGestureRecognizer] {
        let gestureRecognizers: [UIGestureRecognizer?] = [
            panGestureRecognizer,
            screenEdgePanGestureRecognizer,
            tapGestureRecognizer
        ]

        return gestureRecognizers.flatMap { $0 }
    }

    // MARK: - Initializers
    internal required init(animation: MenuAnimation) {
        self.animation = animation
        super.init()
    }

    // MARK: - Instance Methods
    private func makeAffineTranform(for actions: [MenuAnimation.Action]) -> CGAffineTransform {
        let transforms = actions.map { action -> CGAffineTransform in
            switch action {
            case let .translate(x, y):
                return CGAffineTransform(translationX: x, y: y)

            case let .scale(x, y):
                return CGAffineTransform(scaleX: x, y: y)

            case let .rotate(z):
                return CGAffineTransform(rotationAngle: z)
            }
        }

        return transforms.reduce(CGAffineTransform.identity) { $0.concatenating($1) }
    }

    private func calculateScale(for actions: [MenuAnimation.Action]) -> CGPoint {
        var scale = CGPoint(x: 1, y: 1)
        actions.forEach { action in
            switch action {
            case let .scale(x, y):
                scale.x *= x
                scale.y *= y

            default:
                break
            }
        }

        return scale
    }

    fileprivate func calculateScreenEdgePanGestureRectEdges(for actions: [MenuAnimation.Action]) -> UIRectEdge {
        let transform = makeAffineTranform(for: actions)
        var edges = UIRectEdge()

        if transform.tx > 0 {
            edges.formUnion(.left)
        } else if transform.tx < 0 {
            edges.formUnion(.right)
        }

        if transform.ty > 0 {
            edges.formUnion(.top)
        } else if transform.ty < 0 {
            edges.formUnion(.bottom)
        }

        return edges
    }

    fileprivate func calculateAnimationProgress(forTranslation translation: CGPoint, menuState: AnyMenuViewController.MenuState) -> CGFloat {
        let scale = calculateScale(for: animation.contentViewActions)
        var a = CGPoint(x: initialContentViewTransform.tx, y: initialContentViewTransform.ty)
        var b = CGPoint(x: finalContentViewTransform.tx, y: finalContentViewTransform.ty)
        a.x *= (1 / scale.x)
        a.y *= (1 / scale.y)
        b.x *= (1 / scale.x)
        b.y *= (1 / scale.y)

        if menuState == .open {
            (a, b) = (CGPoint(x: -b.x, y: -b.y), CGPoint(x: -a.x, y: -a.y))
        }

        // Projects translation to line between initial and final translation
        let at = CGPoint(x: translation.x - a.x, y: translation.y - a.y)
        let ab = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let d = (at.x * ab.x + at.y * ab.y) / (ab.x * ab.x + ab.y * ab.y)

        return max(0, min(1, d))
    }

    fileprivate func interpolateTransform(from fromTransform: CGAffineTransform, to toTransform: CGAffineTransform, progress: CGFloat) -> CGAffineTransform {
        let lerp = { (a: CGFloat, b: CGFloat, p: CGFloat) -> CGFloat in // swiftlint:disable:this identifier_name
            return a + (b - a) * p
        }

        return CGAffineTransform(
            a: lerp(fromTransform.a, toTransform.a, progress),
            b: lerp(fromTransform.b, toTransform.b, progress),
            c: lerp(fromTransform.c, toTransform.c, progress),
            d: lerp(fromTransform.d, toTransform.d, progress),
            tx: lerp(fromTransform.tx, toTransform.tx, progress),
            ty: lerp(fromTransform.ty, toTransform.ty, progress)
        )
    }

    fileprivate func snapViewController(forceCollapse: Bool?, animated: Bool, duration: TimeInterval, velocity: CGPoint = .zero, progress: CGFloat) {
        let rectEdges = calculateScreenEdgePanGestureRectEdges(for: animation.contentViewActions)
        let forceVelocityThreshold: CGFloat = 1_000
        var forceCollapse = forceCollapse
        var duration = duration

        if rectEdges.contains(.left) && velocity.x <= -forceVelocityThreshold {
            forceCollapse = true
        }

        if rectEdges.contains(.right) && velocity.x >= forceVelocityThreshold {
            forceCollapse = true
        }

        if rectEdges.contains(.top) && velocity.y <= -forceVelocityThreshold {
            forceCollapse = true
        }

        if rectEdges.contains(.bottom) && velocity.y >= forceVelocityThreshold {
            forceCollapse = true
        }

        var willCollapse = progress < 0.5
        if forceCollapse != nil {
            willCollapse = forceCollapse!
        }

        if rectEdges.contains(.left) && velocity.x >= forceVelocityThreshold {
            willCollapse = false
        }

        if rectEdges.contains(.right) && velocity.x <= -forceVelocityThreshold {
            willCollapse = false
        }

        if rectEdges.contains(.top) && velocity.y >= forceVelocityThreshold {
            willCollapse = false
        }

        if rectEdges.contains(.bottom) && velocity.y <= -forceVelocityThreshold {
            willCollapse = false
        }

        let targetMenuViewTransform = willCollapse ? initialMenuViewTransform! : finalMenuViewTransform!
        let targetContentViewTransform = willCollapse ? initialContentViewTransform! : finalContentViewTransform!
        let targetMenuState: AnyMenuViewController.MenuState = willCollapse ? .closed : .open

        if animated {
            duration = willCollapse ? duration * TimeInterval(1 - progress) : duration * TimeInterval(progress)

            UIView.animate(withDuration: duration, delay: 0, options: .layoutSubviews, animations: {
                self.viewController.menuContainerView.transform = targetMenuViewTransform
                self.viewController.contentContainerView.transform = targetContentViewTransform
            }, completion: { _ in
                self.viewController.menuState = targetMenuState
            })
        } else {
            self.viewController.menuContainerView.transform = targetMenuViewTransform
            self.viewController.contentContainerView.transform = targetContentViewTransform
            self.viewController.menuState = targetMenuState
        }
    }

    private func configureGestureRecognizers() {
        gestureRecognizers.forEach { gestureRecognizer in
            gestureRecognizer.view!.removeGestureRecognizer(gestureRecognizer)
        }

        panGestureRecognizer = nil
        screenEdgePanGestureRecognizer = nil
        tapGestureRecognizer = nil

        if true {
            panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
            panGestureRecognizer!.minimumNumberOfTouches = 1
            panGestureRecognizer!.maximumNumberOfTouches = 1

            screenEdgePanGestureRecognizer = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
            screenEdgePanGestureRecognizer!.minimumNumberOfTouches = 1
            screenEdgePanGestureRecognizer!.maximumNumberOfTouches = 1
            screenEdgePanGestureRecognizer!.edges = calculateScreenEdgePanGestureRectEdges(for: animation.contentViewActions)
            screenEdgePanGestureRecognizer!.require(toFail: panGestureRecognizer!)

            tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTapGesture(_:)))
            tapGestureRecognizer!.numberOfTapsRequired = 1
            tapGestureRecognizer!.numberOfTouchesRequired = 1

            // Add gesture recognizer priority to overlay view controller if contains scroll view
            let scrollViews = viewController.contentContainerView.viewsInHierarchy(ofType: UIScrollView.self)
            let gestureRecognizers = scrollViews.flatMap { $0.gestureRecognizers ?? [] }

            for gestureRecognizer in gestureRecognizers where gestureRecognizer is UIPanGestureRecognizer {
                gestureRecognizer.require(toFail: panGestureRecognizer!)
                gestureRecognizer.require(toFail: screenEdgePanGestureRecognizer!)
            }
        }

        gestureRecognizers.forEach { [unowned self] gestureRecognizer in
            gestureRecognizer.delegate = self
            self.viewController.contentContainerView.addGestureRecognizer(gestureRecognizer)
        }
    }

    func configure(forViewController viewController: AnyMenuViewController) {
        self.viewController = viewController

        initialMenuViewTransform = viewController.menuContainerView.transform
        finalMenuViewTransform = makeAffineTranform(for: animation.menuViewActions)
        initialContentViewTransform = viewController.contentContainerView.transform
        finalContentViewTransform = makeAffineTranform(for: animation.contentViewActions)

        configureGestureRecognizers()
    }

    func startAnimation(for menuState: AnyMenuViewController.MenuState) {
        let targetMenuViewTransform = menuState == .open ? finalMenuViewTransform! : initialMenuViewTransform!
        let targetContentViewTransform = menuState == .open ? finalContentViewTransform! : initialContentViewTransform!

        UIView.animate(withDuration: animation.duration, delay: 0, options: .layoutSubviews, animations: {
            self.viewController.menuContainerView.transform = targetMenuViewTransform
            self.viewController.contentContainerView.transform = targetContentViewTransform
        }, completion: nil)
    }
}

// MARK: - Gesture Recognition
extension AnyMenuViewAnimator {
    @objc
    fileprivate func handlePanGesture(_ gestureRecognizer: UIPanGestureRecognizer) {
        switch gestureRecognizer.state {
        case .changed:
            let translation = gestureRecognizer.translation(in: viewController.view)
            let progress = calculateAnimationProgress(forTranslation: translation, menuState: viewController.menuState)
            self.viewController.menuContainerView.transform = interpolateTransform(
                from: initialMenuViewTransform, to: finalMenuViewTransform, progress: progress
            )
            self.viewController.contentContainerView.transform = interpolateTransform(
                from: initialContentViewTransform, to: finalContentViewTransform, progress: progress
            )

        case .ended, .cancelled:
            let velocity = gestureRecognizer.velocity(in: viewController.view)
            let translation = gestureRecognizer.translation(in: viewController.view)
            let progress = calculateAnimationProgress(forTranslation: translation, menuState: viewController.menuState)
            snapViewController(forceCollapse: nil, animated: true, duration: animation.duration, velocity: velocity, progress: progress)

        default:
            break
        }
    }

    @objc
    fileprivate func handleTapGesture(_ gestureRecognizer: UITapGestureRecognizer) {
        if gestureRecognizer.state == .ended {
            snapViewController(forceCollapse: true, animated: true, duration: animation.duration, velocity: .zero, progress: 0)
        }
    }
}

// MARK: - UIGestureRecognizerDelegate Protocol Implementation
extension AnyMenuViewAnimator: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === panGestureRecognizer {
            guard viewController.menuState == .open else { return false }

            let velocity = panGestureRecognizer!.velocity(in: viewController.view)
            let edges = calculateScreenEdgePanGestureRectEdges(for: animation.contentViewActions)

            return ((edges.contains(.top) || edges.contains(.bottom)) && abs(velocity.y) > abs(velocity.x)) || ((edges.contains(.left) || edges.contains(.right)) && abs(velocity.x) > abs(velocity.y))

        } else if gestureRecognizer === screenEdgePanGestureRecognizer {
            return viewController.menuState == .closed
        } else if gestureRecognizer === tapGestureRecognizer {
            return viewController.menuState == .open
        }

        return true
    }
}