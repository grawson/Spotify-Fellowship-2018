//
//  EventDetailsViewController.swift
//  Calendar Frontend
//
//  Created by Gavi Rawson on 6/20/18.
//  Copyright © 2018 Graws Inc. All rights reserved.
//

import UIKit

protocol EventFormDelegate {
    func didCompleteForm(event: Event?, wasEdited: Bool)
}

class EventDetailsViewController: UIViewController {

    // MARK:  Var
    // ********************************************************************************************
    
    fileprivate struct Const {
        static let pickerCell = "pickerCell"
        static let fieldCellID = "fieldCell"
        static let cellHeight: CGFloat = 50
    }
    
    var delegate: EventFormDelegate?
    var selectedDate: Date? { didSet { tableView.reloadData() } }  // the selected date in the calendar
    
    var event: Event? {     // the event to edit
        didSet {
            deleteButton.isHidden = event == nil
            tableView.reloadData()
        }
    }
    
    fileprivate var closeButton: UIBarButtonItem!
    fileprivate var saveButton: UIBarButtonItem!
    fileprivate var constraints = [NSLayoutConstraint]()
    
    lazy fileprivate var deleteButton: UIButton = {
        let x = UIButton()
        x.set(title: "Delete", states: [.normal], forStyle: LabelStyle.button)
        x.contentEdgeInsets = UIEdgeInsets(top: 100, left: 0, bottom: 0, right: 0)
        x.addTarget(self, action: #selector(deleteTapped(_:)), for: .touchUpInside)
        return x
    }()
    
    lazy fileprivate var tableView: UITableView = {
        let x = UITableView(frame: .zero, style: .grouped)
        x.register(DatePickerTableViewCell.self, forCellReuseIdentifier: Const.pickerCell)
        x.register(FieldTableViewCell.self, forCellReuseIdentifier: Const.fieldCellID)
        x.allowsSelection = false
        x.backgroundColor = Colors.blue1
        x.separatorColor = Colors.separator
        return x
    }()

    
    // MARK:  Life cycle
    // ********************************************************************************************
    
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = event == nil ? "New Event" : "Edit Event"
        view.backgroundColor = UIColor.white
        initViews()
        updateLayout()
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent   // Make light status bar
    }
    
    // MARK:  Func
    // ********************************************************************************************
    
    
    fileprivate func initViews() {
        
        // bar buttons
        closeButton = UIBarButtonItem(title: "Close", style: .plain, target: self, action: #selector(closeTapped(_:)))
        navigationItem.leftBarButtonItem = closeButton
        saveButton = UIBarButtonItem(title: "Save", style: .plain, target: self, action: #selector(saveTapped(_:)))
        navigationItem.rightBarButtonItem = saveButton
        
        tableView.dataSource = self
        tableView.delegate = self
        
        view.addSubview(tableView)
        view.addSubview(deleteButton)
    }
    
    fileprivate func updateLayout() {
        view.removeConstraints(constraints)
        constraints = []
        
        let views = [ tableView, deleteButton ]
        let metrics = [Layout.margin * 2]
        let formats = [
            "H:|[v0]|",
            "V:|[v0]|",
            "V:[v1]-(m0)-|"
        ]

        constraints = view.createConstraints(withFormats: formats, metrics: metrics, views: views)
        constraints += [ deleteButton.centerXAnchor.constraint(equalTo: view.centerXAnchor) ]
        view.addConstraints(constraints)
    }
    
    fileprivate func close() {
        dismiss(animated: true, completion: nil)
    }
    
    fileprivate func validateForm() {
        var error: String?
        
        saveButton.isEnabled = false
        
        defer {
            if let error = error {
                let alert = UIAlertController(title: "Uh Oh", message: error, preferredStyle: .alert)
                let ok = UIAlertAction(title: "OK", style: .default, handler: nil)
                alert.addAction(ok)
                present(alert, animated: true, completion: nil)
                saveButton.isEnabled = true
            }
        }
        
        // Get cells
        let titleCell = tableView.cellForRow(at: IndexPath(row: 0, section: 0)) as! FieldTableViewCell
        let startCell = tableView.cellForRow(at: IndexPath(row: 0, section: 1)) as! DatePickerTableViewCell
        let endCell = tableView.cellForRow(at: IndexPath(row: 1, section: 1)) as! DatePickerTableViewCell
        
        guard let title = titleCell.title else {
            error = "Must set a title for the event."
            return
        }
        
        guard let start = startCell.selectedDate else {
            error = "Must select a start date."
            return
        }
        
        guard let end = endCell.selectedDate else {
            error = "Must select an end date."
            return
        }
        
        guard start < end else {
            error = "Start date must be before the end date."
            return
        }
        
        // update vent if editing
        if event != nil {
            event?.title = title
            event?.endDate = end
            event?.startDate = start
        }
        
        let newEvent = event == nil ? Event(title: title, start: start, end: end) : event!
        
        if self.event == nil {  // save
            EventsManager.shared.saveEvent(newEvent) { [weak self] (success) in
                self?.finish(success: success, event: newEvent)
            }
        } else { // update
            EventsManager.shared.updateEvent(newEvent) { [weak self] (success) in
                self?.finish(success: success, event: newEvent)
            }
        }
    }
    
    // finish saving or updating an event
    fileprivate func finish(success: Bool, event: Event?) {
        defer {
            saveButton.isEnabled = true
        }
        
        // present alert on error
        guard success else {
            let alert = UIAlertController(title: "Uh Oh", message: "Failed to save event to database.", preferredStyle: .alert)
            let ok = UIAlertAction(title: "OK", style: .default, handler: nil)
            alert.addAction(ok)
            
            DispatchQueue.main.async { [weak self] in
                self?.present(alert, animated: true, completion: nil)
            }
            return
        }
        
        delegate?.didCompleteForm(event: event, wasEdited: self.event != nil)
        close()
    }
    
    
    // MARK:  Event Listeners
    // ********************************************************************************************
    
    @objc fileprivate func closeTapped(_ sender: UIBarButtonItem) {
        close()
    }
    
    @objc fileprivate func saveTapped(_ sender: UIBarButtonItem) {
        validateForm()
    }
    
    @objc func deleteTapped(_ sender: UIButton) {
        
        let alert = UIAlertController(title: "Delete", message: "Are you sure you want to delete this event?", preferredStyle: .alert)
        
        let yes = UIAlertAction(title: "Yes", style: .destructive) { [weak self] (action) in
            guard let sSelf = self else { return }
            EventsManager.shared.deleteEvent(sSelf.event!) { (success) in
                sSelf.finish(success: success, event: nil)
            }
        }
        
        let cancel = UIAlertAction(title: "Cancel", style: .default, handler: nil)
        alert.addAction(yes)
        alert.addAction(cancel)
        present(alert, animated: true, completion: nil)
    }
}

// MARK:  Table view delegate
// ********************************************************************************************

extension EventDetailsViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 1
        case 1: return 2
        default: return 0
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        if indexPath.section == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: Const.fieldCellID, for: indexPath as IndexPath) as! FieldTableViewCell
            cell.title = event?.title
            return cell
            
        } else {
            let cell = tableView.dequeueReusableCell(withIdentifier: Const.pickerCell, for: indexPath as IndexPath) as! DatePickerTableViewCell
            cell.directions = indexPath.row == 0 ? "Start" : "End"
            
            if let event = event {  // editing
                cell.selectedDate = indexPath.row == 0 ? event.startDate : event.endDate
            
            } else if selectedDate != nil {   // adding new event
                cell.selectedDate = selectedDate
            }
            
            return cell
        }
    }
}

// MARK: table view delegate
// ********************************************************************************************

extension EventDetailsViewController: UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return Const.cellHeight
    }
}




