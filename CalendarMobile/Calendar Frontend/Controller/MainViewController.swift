//
//  MainViewController.swift
//  Calendar Frontend
//
//  Created by Gavi Rawson on 6/18/18.
//  Copyright © 2018 Graws Inc. All rights reserved.
//

import UIKit

class MainViewController: UIViewController {
    
    // MARK:  Var
    // ********************************************************************************************
    
    fileprivate struct Const {
        static let cellID = "monthCell"
        static let eventCell = "eventCell"
        static let yearFmt = "yyyy"
        static let monthFmt = "MMMM"
        static let mappingFmt = "yyyy-MM-dd"
        static let cellFmt = "h:mm a"
        static let cellFullFmt = "h:mm a (MMM d)"
        static let loadingBatchSize = 3     // number of months to load in a batch (must be greater than 1)
    }
    
    fileprivate var eventsMapping = [String: Int]()           // Maps date string to index of events in events array
    fileprivate var events = [[Event]]()
    fileprivate var months = [Date]()                        // months loaded into collection view (stored as first day of months)
    
    fileprivate var selectedDate: Date?                      // date selected (circled in calendar)
    
    fileprivate var displayedEvents: Int?  { didSet { reloadTable() } }  // index for events displayed in the table view
    fileprivate var editingIndex: Int?                       // index in events array of event currently editing
    fileprivate var editingKey: String?                      // key for eventMapping leading to event array containning event currently editing
    
    fileprivate var todayIndex = Const.loadingBatchSize      // index for today in the months array
    fileprivate var initialScroll = false                    // flag true if have scrolled to this month on load
    fileprivate var indexOfCellBeforeDragging = 0            // Used for calculating cell snapping
    
    fileprivate var formatter: DateFormatter = {
        let x = DateFormatter()
        x.calendar = Calendar.current
        x.timeZone = Calendar.current.timeZone
        return x
    }()
    
    fileprivate var constraints = [NSLayoutConstraint]()
    
    fileprivate var monthLabel: UILabel = { return UILabel() }()
    fileprivate var yearLabel: UILabel = { return UILabel() }()

    fileprivate var displayedDate: Date? {      // update the currently displayed date in the collection view
        didSet {
            guard let date = displayedDate else { return }
            
            // set year and month header labels
            formatter.dateFormat = Const.monthFmt
            monthLabel.set(title: formatter.string(from: date), forStyle: LabelStyle.strongTitle)
            formatter.dateFormat = Const.yearFmt
            yearLabel.set(title: formatter.string(from: date), forStyle: LabelStyle.lightTitle)
        }
    }
    
    fileprivate var separator: UIView = {
        let x = UIView()
        x.backgroundColor = Colors.separator
        return x
    }()
    
    fileprivate var addEventButton: UIButton = {
        let x = UIButton()
        x.setImage(UIImage(named: "plus")?.withRenderingMode(.alwaysTemplate), for: .normal)
        x.tintColor = Colors.tint
        x.addTarget(self, action: #selector(addEventClicked(_:)), for: .touchUpInside)
        return x
    }()
    
    fileprivate var dayLabels: UIStackView = {
        let x = UIStackView()
        x.axis = .horizontal
        x.distribution = .equalCentering
        
        // Day labels
        let days = ["S", "M", "T", "W", "T", "F", "S"]
        for day in days {
            let label = UILabel()
            label.set(title: day, forStyle: LabelStyle.button)
            x.addArrangedSubview(label)
        }
        return x
    }()
    
    lazy fileprivate var eventsTableView: UITableView = {
        let x = UITableView(frame: .zero, style: .plain)
        x.backgroundColor = Colors.blue3
        x.separatorColor = Colors.separator
        x.register(EventTableViewCell.self, forCellReuseIdentifier: Const.eventCell)
        x.estimatedRowHeight = UITableView.automaticDimension
        x.tableFooterView = UIView()
        
        // shadow
        x.layer.shadowColor = UIColor.black.cgColor
        x.layer.shadowOpacity = 0.15
        x.layer.shadowOffset = .zero
        x.layer.shadowRadius = 5
        return x
    }()
    
    fileprivate var emptyTableLabel: UILabel = {
        let x = UILabel()
        x.set(title: "No Events.", forStyle: LabelStyle.fadedHeader)
        return x
    }()
    
    fileprivate var monthCollectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0.5

        let x = UICollectionView(frame: .zero, collectionViewLayout: layout)
        x.backgroundColor = Colors.separator
        x.clipsToBounds = false
        x.register(MonthCollectionViewCell.self, forCellWithReuseIdentifier: Const.cellID)
        x.showsHorizontalScrollIndicator = false
        return x
    }()
    
    
    // MARK:  Life Cycle
    // ********************************************************************************************
    
    override func viewDidLoad() {
        super.viewDidLoad()
        initViews()
        updateLayout()
        initMonths()

        displayedDate = months[todayIndex]
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // collection view sizing
        let layout = monthCollectionView.collectionViewLayout as! UICollectionViewFlowLayout
        layout.itemSize = CGSize(width: view.frame.width, height: monthCollectionView.frame.height)
        
        // scroll to today on load
        if !initialScroll {
            monthCollectionView.scrollToItem(at: IndexPath(row: todayIndex, section: 0), at: .centeredHorizontally, animated: false)
            initialScroll = true
        }
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent   // Make light status bar
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if let index = eventsTableView.indexPathForSelectedRow {
            eventsTableView.deselectRow(at: index, animated: true)
        }
    }
    
    // MARK:  Func
    // ********************************************************************************************
    
    // Add an event to the even mapping data structure
    fileprivate func updateEventMapping(event: Event) {
        formatter.dateFormat = Const.mappingFmt
        let key = formatter.string(from: event.startDate)
        
        if eventsMapping[key] == nil {
            events.append([Event]())
            eventsMapping[key] = events.count-1
        }
        events[eventsMapping[key]!].append(event)
    }
    
    // Initialize the initial months in the collection view
    fileprivate func initMonths() {
        let offset = Const.loadingBatchSize
        for i in -offset...offset {
            let startOfMonth = Calendar.current.date(byAdding: DateComponents(month: i, day: 0), to: Date())!.startOfMonth()
            months.append(startOfMonth)
        }
        loadEvents(start: months.first!, end: months.last!.endOfMonth())
    }
    
    // load events based on given dates
    fileprivate func loadEvents(start: Date, end: Date) {
        EventsManager.shared.getEvents(start: start, end: end) { [weak self] (events) in
            guard let sSelf = self else { return }
            
            events.forEach { sSelf.updateEventMapping(event: $0) }
            
            DispatchQueue.main.async {
                sSelf.monthCollectionView.reloadData()
                sSelf.reloadTable()
            }
        }
    }
    
    fileprivate func initViews() {
        view.backgroundColor = Colors.blue1
        
        monthCollectionView.delegate = self
        monthCollectionView.dataSource = self
        eventsTableView.dataSource = self
        eventsTableView.delegate = self
        
        view.addSubview(monthCollectionView)
        view.addSubview(monthLabel)
        view.addSubview(yearLabel)
        view.addSubview(eventsTableView)
        view.addSubview(emptyTableLabel)
        view.addSubview(addEventButton)
        view.addSubview(dayLabels)
        view.addSubview(separator)
    }
    
    fileprivate func updateLayout() {
        view.removeConstraints(constraints)
        constraints = []
        
        let views = [
            monthCollectionView, monthLabel, yearLabel,     // 0-2
            eventsTableView, addEventButton, dayLabels,     // 3-5
            separator   // 6-8
        ]
        
        let metrics = [Layout.margin, 20, Layout.margin*2]
        let formats = [
            "H:|[v0]|",
            "H:|-(m0)-[v1]-[v2]",
            "V:|-(40)-[v1]-(m0)-[v5]-(m0)-[v6(0.5)]-[v0(275)]-[v3]|",
            "H:|[v3]|",
            "H:|-(m2)-[v5]-(m2)-|",
            "H:|-(m2)-[v6]-(m2)-|",
            "H:[v4(m1)]-(m2)-|",
            "V:[v4(m1)]"
        ]
        
        constraints = view.createConstraints(withFormats: formats, metrics: metrics, views: views)
        
        emptyTableLabel.translatesAutoresizingMaskIntoConstraints = false
        
        constraints += [
            yearLabel.lastBaselineAnchor.constraint(equalTo: monthLabel.lastBaselineAnchor),
            yearLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -Layout.margin),
            emptyTableLabel.centerXAnchor.constraint(equalTo: eventsTableView.centerXAnchor),
            emptyTableLabel.centerYAnchor.constraint(equalTo: eventsTableView.centerYAnchor),
            yearLabel.trailingAnchor.constraint(lessThanOrEqualTo: addEventButton.leadingAnchor, constant: Layout.margin),
            addEventButton.centerYAnchor.constraint(equalTo: yearLabel.centerYAnchor)
        ]
        
        view.addConstraints(constraints)
    }
    
    // Index of the most visible cell on screen
    fileprivate func indexOfMajorCell() -> Int {
        let layout = monthCollectionView.collectionViewLayout as! UICollectionViewFlowLayout
        let itemWidth = layout.itemSize.width
        let proportionalOffset = monthCollectionView.contentOffset.x / itemWidth
        return Int(round(proportionalOffset))
    }
    
    fileprivate func reloadTable() {
        emptyTableLabel.isHidden = displayedEvents != nil
        
        // only sort displayed events for efficiency sake
        if let index = displayedEvents {
            events[index].sort { $0.startDate < $1.startDate }
        }
        
        eventsTableView.reloadData()
    }
    
    fileprivate func showEventDetails(_ forEvent: Event?) {
        let vc = EventDetailsViewController()
        vc.delegate = self
        vc.event = forEvent
        vc.selectedDate = selectedDate
        let nav = UINavigationController(rootViewController: vc)
        present(nav, animated: true, completion: nil)
    }
    
    // MARK:  Event listener
    // ********************************************************************************************
    
    @objc fileprivate func addEventClicked(_ sender: UIButton) {
        showEventDetails(nil)
    }

}



// MARK: Collection view data source
// ********************************************************************************************

extension MainViewController: UICollectionViewDataSource {
    
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return months.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: Const.cellID, for: indexPath) as! MonthCollectionViewCell
        cell.eventsMapping = eventsMapping
        cell.date = months[indexPath.row]
        cell.update()
        cell.delegate = self
        
        return cell
    }
}

// MARK: Collection view delegate
// ********************************************************************************************

extension MainViewController: UICollectionViewDelegateFlowLayout {

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        indexOfCellBeforeDragging = indexOfMajorCell()
    }
    
    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        targetContentOffset.pointee = scrollView.contentOffset   // Stop scrollView sliding
        let indexOfMajorCell = self.indexOfMajorCell()           // calculate where scrollView should snap to
        
        // calculate conditions for snapping
        let swipeVelocityThreshold: CGFloat = 0.5
        let hasEnoughVelocityToSlideToTheNextCell = indexOfCellBeforeDragging + 1 < months.count && velocity.x > swipeVelocityThreshold
        let hasEnoughVelocityToSlideToThePreviousCell = indexOfCellBeforeDragging - 1 >= 0 && velocity.x < -swipeVelocityThreshold
        let majorCellIsTheCellBeforeDragging = indexOfMajorCell == indexOfCellBeforeDragging
        let didUseSwipeToSkipCell = majorCellIsTheCellBeforeDragging && (hasEnoughVelocityToSlideToTheNextCell || hasEnoughVelocityToSlideToThePreviousCell)
        
        // Snap to cell
        let snapToIndex = didUseSwipeToSkipCell ? indexOfCellBeforeDragging + (hasEnoughVelocityToSlideToTheNextCell ? 1 : -1) : indexOfMajorCell
        monthCollectionView.scrollToItem(at: IndexPath(row: snapToIndex, section: 0), at: .centeredHorizontally, animated: true)

        // Update header labels for year and month if displaying a new cell
        if snapToIndex != indexOfCellBeforeDragging {
            displayedDate = months[snapToIndex]
        }
    }
    
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        let indexOfMajorCell = self.indexOfMajorCell()                                      // Currently displayed cell index
        let monthsNeedUpdate = indexOfMajorCell <= 2 || indexOfMajorCell >= months.count-3  // Need to load new months
        let updateBeginning = monthsNeedUpdate && indexOfMajorCell <= 2                     // update beginning of months array

        if monthsNeedUpdate {

            // Load batch of months
            for _ in 0..<Const.loadingBatchSize {
                let referenceDate = updateBeginning ? months.first! : months.last!
                let toAdd = Calendar.current.date(byAdding: DateComponents(month: updateBeginning ? -1 : 1, day: 0), to: referenceDate)!.startOfMonth()
                updateBeginning ? months.insert(toAdd, at: 0) : months.append(toAdd)
                todayIndex += updateBeginning ? 1 : -1
            }
            
            // Load events for new months
            let firstMonth = months[updateBeginning ? 0 : months.count-1]
            let lastMonth = months[updateBeginning ? Const.loadingBatchSize-1 : (months.count-1) - (Const.loadingBatchSize-1)].endOfMonth()
            loadEvents(start: firstMonth, end: lastMonth)
            
            // Reload and scroll to correct position
            monthCollectionView.reloadData()    // TODO: Innefficient to reload all cells
            if updateBeginning {
                monthCollectionView.scrollToItem(at: IndexPath(row:indexOfMajorCell+Const.loadingBatchSize, section: 0), at: .centeredHorizontally, animated: false)
            }
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        // clear today selection if vc is visible
        guard self.isViewLoaded && (self.view.window != nil) else { return }
        (cell as! MonthCollectionViewCell).clearToday()
        displayedEvents = nil
    }
}

// MARK:  Table view data source
// ********************************************************************************************

extension MainViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let index = displayedEvents else { return 0 }
        return events[index].count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Const.eventCell, for: indexPath as IndexPath) as! EventTableViewCell
        guard let index = displayedEvents else { return cell }
        
        // selection color
        let selection = UIView()
        selection.backgroundColor = Colors.blue4
        cell.selectedBackgroundView = selection

        let event = events[index][indexPath.row]
        cell.title = event.title
        
        formatter.dateFormat = Const.cellFmt
        cell.start = formatter.string(from: event.startDate)
        
        // handles label for multi-day events
        if !Calendar.current.isDate(event.startDate, inSameDayAs: event.endDate) {
            formatter.dateFormat = Const.cellFullFmt
        }
        
        cell.end = formatter.string(from: event.endDate)
        return cell
    }
}

// MARK:  UI Table view delegate
// ********************************************************************************************

extension MainViewController: UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let index = displayedEvents else { return }
        let event = events[index][indexPath.row]
        
        // store vars for later to quixkly update data structure on removal or edit
        editingIndex = indexPath.row
        formatter.dateFormat = Const.mappingFmt
        editingKey = formatter.string(from: event.startDate)
        
        showEventDetails(event)
    }
}


// MARK:  Month Collection view cell delegate
// ********************************************************************************************

extension MainViewController: MonthCollectionViewCellDelegate {
    func didSelectDay(day: Int, month: Int) {
        guard let displayedDate = displayedDate else { return }
        
        var components = DateComponents()
        let referenceComponents = Calendar.current.dateComponents([.year, .month], from: displayedDate)
        
        // update components based on reference month
        components.day = day
        components.year = referenceComponents.year!
        components.month = referenceComponents.month! + month
        
        // Compute the key to lookup to required data
        selectedDate = Calendar.current.date(from: components)
        formatter.dateFormat = Const.mappingFmt
        let key = formatter.string(from: selectedDate!)
        
        // Set table view data. Will be nil if it doesnt exist in the mapping
        displayedEvents = eventsMapping[key]
    }
}

// MARK:  Event form delegate
// ********************************************************************************************

extension MainViewController: EventFormDelegate {
    
    func didCompleteForm(event: Event?, wasEdited: Bool) {
        
        // remove if edited in case the start date has changed
        if wasEdited {
            events[displayedEvents!].remove(at: editingIndex!)  // remove event
            
            if events[displayedEvents!].count == 0 {    // remove mapping to event
                eventsMapping[editingKey!] = nil
            }
        }
        
        if let event = event {
            updateEventMapping(event: event)
        }
        
        // Reload only months containing event
        var toReload = [IndexPath]()
        let components = Calendar.current.dateComponents([.month, .year], from: selectedDate!)
        for i in 0..<months.count {
            let toCompare = Calendar.current.dateComponents([.month, .year], from: months[i])
            if toCompare.month! == components.month! && toCompare.year! == components.year! {
                
                // Reload same month
                toReload.append(IndexPath(row: i, section: 0))
                
                // Reload previous month
                if i > 0 {
                    toReload.append(IndexPath(row: i-1, section: 0))
                }
                
                // Reload next month
                if i < months.count-1 {
                    toReload.append(IndexPath(row: i+1, section: 0))
                }
            }
        }
        
        // Reload
        monthCollectionView.reloadItems(at: toReload)
        reloadTable()
    }
}



