import UIKit

final class TOTPCodeCell: UICollectionViewCell {
    static let reuseID = "TOTPCodeCell"

    private var account: Account?

    // MARK: - UI

    private let iconView: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 18
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let iconLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 14, weight: .bold)
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let issuerLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 13, weight: .semibold)
        l.textColor = .label
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let labelLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 10, weight: .regular)
        l.textColor = .secondaryLabel
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let codeLabel: UILabel = {
        let l = UILabel()
        l.font = .monospacedSystemFont(ofSize: 22, weight: .bold)
        l.textColor = .label
        l.textAlignment = .right
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let tapHintLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 9, weight: .medium)
        l.textColor = .tertiaryLabel
        l.text = "TAP TO INSERT"
        l.textAlignment = .right
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let countdownRing = CAShapeLayer()
    private let countdownBg = CAShapeLayer()

    private let countdownLabel: UILabel = {
        let l = UILabel()
        l.font = .monospacedSystemFont(ofSize: 10, weight: .semibold)
        l.textColor = .systemBlue
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let ringContainer: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupUI() {
        contentView.backgroundColor = .secondarySystemBackground
        contentView.layer.cornerRadius = 12
        contentView.clipsToBounds = true

        iconView.addSubview(iconLabel)
        contentView.addSubview(iconView)
        contentView.addSubview(issuerLabel)
        contentView.addSubview(labelLabel)
        contentView.addSubview(codeLabel)
        contentView.addSubview(tapHintLabel)
        contentView.addSubview(ringContainer)
        ringContainer.addSubview(countdownLabel)

        NSLayoutConstraint.activate([
            // Icon
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 36),
            iconView.heightAnchor.constraint(equalToConstant: 36),

            iconLabel.centerXAnchor.constraint(equalTo: iconView.centerXAnchor),
            iconLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),

            // Issuer + label
            issuerLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            issuerLabel.bottomAnchor.constraint(equalTo: contentView.centerYAnchor, constant: -1),

            labelLabel.leadingAnchor.constraint(equalTo: issuerLabel.leadingAnchor),
            labelLabel.topAnchor.constraint(equalTo: contentView.centerYAnchor, constant: 2),
            labelLabel.trailingAnchor.constraint(lessThanOrEqualTo: codeLabel.leadingAnchor, constant: -8),

            // Code
            codeLabel.trailingAnchor.constraint(equalTo: ringContainer.leadingAnchor, constant: -10),
            codeLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: -6),

            // Tap hint
            tapHintLabel.trailingAnchor.constraint(equalTo: codeLabel.trailingAnchor),
            tapHintLabel.topAnchor.constraint(equalTo: codeLabel.bottomAnchor, constant: 1),

            // Ring
            ringContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            ringContainer.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            ringContainer.widthAnchor.constraint(equalToConstant: 28),
            ringContainer.heightAnchor.constraint(equalToConstant: 28),

            countdownLabel.centerXAnchor.constraint(equalTo: ringContainer.centerXAnchor),
            countdownLabel.centerYAnchor.constraint(equalTo: ringContainer.centerYAnchor),
        ])

        // Ring layers
        let ringPath = UIBezierPath(
            arcCenter: CGPoint(x: 14, y: 14),
            radius: 12,
            startAngle: -.pi / 2,
            endAngle: 3 * .pi / 2,
            clockwise: true
        )

        countdownBg.path = ringPath.cgPath
        countdownBg.fillColor = UIColor.clear.cgColor
        countdownBg.strokeColor = UIColor.systemBlue.withAlphaComponent(0.15).cgColor
        countdownBg.lineWidth = 2.5
        ringContainer.layer.addSublayer(countdownBg)

        countdownRing.path = ringPath.cgPath
        countdownRing.fillColor = UIColor.clear.cgColor
        countdownRing.strokeColor = UIColor.systemBlue.cgColor
        countdownRing.lineWidth = 2.5
        countdownRing.lineCap = .round
        countdownRing.strokeEnd = 1.0
        ringContainer.layer.addSublayer(countdownRing)
    }

    // MARK: - Configure

    func configure(with account: Account) {
        self.account = account
        let issuer = account.issuer.isEmpty
            ? (account.label.components(separatedBy: "@").last ?? "Account")
            : account.issuer
        issuerLabel.text = issuer
        labelLabel.text = account.label

        // Icon
        let colors: [UIColor] = [.systemBlue, .systemPurple, .systemOrange, .systemTeal, .systemPink, .systemIndigo, .systemMint]
        let color = colors[abs(account.issuer.hashValue) % colors.count]
        iconView.backgroundColor = color.withAlphaComponent(0.15)
        iconLabel.textColor = color
        iconLabel.text = String(issuer.prefix(1)).uppercased()

        refreshDisplay()
    }

    func refreshDisplay() {
        guard let account else { return }
        let now = Date()
        let code = TOTPGenerator.generate(for: account, at: now) ?? "------"
        let remaining = TOTPGenerator.secondsRemaining(period: account.period, at: now)
        let progress = CGFloat(remaining) / CGFloat(account.period)

        // Format code: "123 456"
        if code.count >= 6 {
            let mid = code.index(code.startIndex, offsetBy: code.count / 2)
            codeLabel.text = "\(code[code.startIndex..<mid]) \(code[mid...])"
        } else {
            codeLabel.text = code
        }

        countdownLabel.text = "\(remaining)"
        countdownRing.strokeEnd = progress

        let ringColor: UIColor = remaining <= 5 ? .systemRed : (remaining <= 10 ? .systemOrange : .systemBlue)
        countdownRing.strokeColor = ringColor.cgColor
        countdownBg.strokeColor = ringColor.withAlphaComponent(0.15).cgColor
        countdownLabel.textColor = ringColor
    }

    // MARK: - Feedback

    func flashInserted() {
        let original = contentView.backgroundColor
        UIView.animate(withDuration: 0.15, animations: {
            self.contentView.backgroundColor = .systemGreen.withAlphaComponent(0.25)
            self.tapHintLabel.text = "INSERTED"
            self.tapHintLabel.textColor = .systemGreen
        }) { _ in
            UIView.animate(withDuration: 0.4) {
                self.contentView.backgroundColor = original
                self.tapHintLabel.text = "TAP TO INSERT"
                self.tapHintLabel.textColor = .tertiaryLabel
            }
        }
    }
}
