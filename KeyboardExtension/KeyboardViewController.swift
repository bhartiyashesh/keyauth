import UIKit

class KeyboardViewController: UIInputViewController {

    // MARK: - State

    private var accounts: [Account] = []
    private var displayTimer: Timer?

    // MARK: - UI Elements

    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 6
        layout.sectionInset = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)

        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .clear
        cv.showsVerticalScrollIndicator = false
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.delegate = self
        cv.dataSource = self
        cv.register(TOTPCodeCell.self, forCellWithReuseIdentifier: TOTPCodeCell.reuseID)
        return cv
    }()

    private lazy var emptyLabel: UILabel = {
        let l = UILabel()
        l.text = "No accounts — add codes in the KeyAuth app"
        l.font = .systemFont(ofSize: 13, weight: .medium)
        l.textColor = .secondaryLabel
        l.textAlignment = .center
        l.numberOfLines = 2
        l.translatesAutoresizingMaskIntoConstraints = false
        l.isHidden = true
        return l
    }()

    private lazy var nextKeyboardButton: UIButton = {
        let btn = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        btn.setImage(UIImage(systemName: "globe", withConfiguration: config), for: .normal)
        btn.tintColor = .secondaryLabel
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        return btn
    }()

    private lazy var titleLabel: UILabel = {
        let l = UILabel()
        l.text = "KeyAuth"
        l.font = .systemFont(ofSize: 13, weight: .bold)
        l.textColor = .label
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private lazy var shieldIcon: UIImageView = {
        let config = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        let iv = UIImageView(image: UIImage(systemName: "lock.shield.fill", withConfiguration: config))
        iv.tintColor = .systemBlue
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadAccounts()
        startTimer()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadAccounts()
        collectionView.reloadData()
        updateEmptyState()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        displayTimer?.invalidate()
        displayTimer = nil
    }

    // MARK: - Data

    private func loadAccounts() {
        accounts = SharedDefaults.loadAccounts()
    }

    private func startTimer() {
        displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.collectionView.visibleCells.forEach { cell in
                (cell as? TOTPCodeCell)?.refreshDisplay()
            }
        }
    }

    private func updateEmptyState() {
        emptyLabel.isHidden = !accounts.isEmpty
        collectionView.isHidden = accounts.isEmpty
    }

    // MARK: - UI Setup

    private func setupUI() {
        guard let inputView = self.inputView else { return }
        inputView.allowsSelfSizing = true

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        inputView.addSubview(container)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: inputView.trailingAnchor),
            container.topAnchor.constraint(equalTo: inputView.topAnchor),
            container.bottomAnchor.constraint(equalTo: inputView.bottomAnchor),
        ])

        // Top bar: globe + title + shield
        let topBar = UIView()
        topBar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(topBar)
        topBar.addSubview(nextKeyboardButton)
        topBar.addSubview(shieldIcon)
        topBar.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            topBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            topBar.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            topBar.heightAnchor.constraint(equalToConstant: 28),

            nextKeyboardButton.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 12),
            nextKeyboardButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            nextKeyboardButton.widthAnchor.constraint(equalToConstant: 28),

            shieldIcon.leadingAnchor.constraint(equalTo: nextKeyboardButton.trailingAnchor, constant: 8),
            shieldIcon.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: shieldIcon.trailingAnchor, constant: 4),
            titleLabel.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
        ])

        // Collection view for codes
        container.addSubview(collectionView)
        container.addSubview(emptyLabel)

        // Target height: enough for ~3 code rows
        let keyboardHeight: CGFloat = 220

        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 4),
            collectionView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),

            container.heightAnchor.constraint(equalToConstant: keyboardHeight),

            emptyLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 40),
            emptyLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -40),
        ])
    }
}

// MARK: - UICollectionView

extension KeyboardViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        accounts.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: TOTPCodeCell.reuseID, for: indexPath) as! TOTPCodeCell
        cell.configure(with: accounts[indexPath.item])
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = collectionView.bounds.width - 16
        return CGSize(width: width, height: 58)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let account = accounts[indexPath.item]
        guard let code = TOTPGenerator.generate(for: account) else { return }
        textDocumentProxy.insertText(code)

        if let cell = collectionView.cellForItem(at: indexPath) as? TOTPCodeCell {
            cell.flashInserted()
        }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}

// MARK: - UIInputViewAudioFeedback

extension KeyboardViewController: UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}
