//
//  NewsSessionManager.swift
//  CloudNews
//
//  Created by Peter Hedlund on 10/20/18.
//  Copyright © 2020 Peter Hedlund. All rights reserved.
//

import Cocoa
import Alamofire

typealias SyncCompletionBlock = () -> Void
typealias SyncCompletionBlockNewItems = (_ newItems: [ItemProtocol]) -> Void

class NewsManager {
    
    static let shared = NewsManager()
    
    private let session: Session
    
    var syncTimer: Timer?
    
    init() {
        session = Session()
        self.setupSyncTimer()
    }
    
    func setupSyncTimer() {
        self.syncTimer?.invalidate()
        self.syncTimer = nil
        let interval = UserDefaults.standard.integer(forKey: "interval")
        if interval > 0 {
            var timeInterval: TimeInterval = 900
            switch interval {
            case 2: timeInterval = 30 * 60
            case 3: timeInterval = 60 * 60
            default: timeInterval = 15 * 60
            }
            self.syncTimer = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: true) { (_) in
                NotificationCenter.default.post(name: .syncInitiated, object: nil)
                self.sync(completion: {
                    NotificationCenter.default.post(name: .syncComplete, object: nil)
                })
            }
        }
    }
    
    func addFeed(url: String) {
        let router = Router.createFeed(url: url, folder: 0)
        
        session.request(router).responseDecodable(of: Feeds.self) { response in
            switch response.result {
            case let .success(result):
                print(result)
            case let .failure(error):
                print(error.localizedDescription)
            }
        }
    }
    
    func addFolder(name: String) {
        let router = Router.createFolder(name: name)
        
        session.request(router).responseDecodable(of: Folders.self) { response in
            switch response.result {
            case let .success(result):
                print(result)
            case let .failure(error):
                print(error.localizedDescription)
            }
        }
    }
    
    func markRead(itemIds: [Int32], state: Bool, completion: @escaping SyncCompletionBlock) {
        CDItem.markRead(itemIds: itemIds, state: state) {
            completion()
            let parameters: Parameters = ["items": itemIds]
            var router: Router
            if state {
                router = Router.itemsUnread(parameters: parameters)
            } else {
                router = Router.itemsRead(parameters: parameters)
            }
            session.request(router).responseData { response in
                switch response.result {
                case .success:
                    if state {
                        CDUnread.deleteItemIds(itemIds: itemIds, in: NewsData.mainThreadContext)
                    } else {
                        CDRead.deleteItemIds(itemIds: itemIds, in: NewsData.mainThreadContext)
                    }
                case .failure(let error):
                    print(error.localizedDescription)
                }
            }
        }
    }
    
    func markStarred(item: CDItem, starred: Bool, completion: @escaping SyncCompletionBlock) {
        CDItem.markStarred(itemId: item.id, state: starred) {
            completion()
            let parameters: Parameters = ["items": [["feedId": item.feedId,
                                                     "guidHash": item.guidHash as Any]]]
            var router: Router
            if starred {
                router = Router.itemsStarred(parameters: parameters)
            } else {
                router = Router.itemsUnstarred(parameters: parameters)
            }
            session.request(router).responseData { response in
                switch response.result {
                case .success:
                    if starred {
                        CDStarred.deleteItemIds(itemIds: [item.id], in: NewsData.mainThreadContext)
                    } else {
                        CDUnstarred.deleteItemIds(itemIds: [item.id], in: NewsData.mainThreadContext)
                    }
                case .failure(let error):
                    print(error.localizedDescription)
                }
                completion()
            }
        }
    }
    
    /*
     Initial sync
     
     1. unread articles: GET /items?type=3&getRead=false&batchSize=-1
     2. starred articles: GET /items?type=2&getRead=true&batchSize=-1
     3. folders: GET /folders
     4. feeds: GET /feeds
     */
    
    func initialSync() {
        
        // 1.
        let unreadParameters: Parameters = ["type": 3,
                                            "getRead": false,
                                            "batchSize": -1]
        
        let unreadItemRouter = Router.items(parameters: unreadParameters)
        session.request(unreadItemRouter).responseDecodable(of: Items.self) { [weak self] response in
            switch response.result {
            case let .success(result):
                if let items = result.items {
                    CDItem.update(items: items, completion: nil)
                    self?.updateBadge()
                }
            case let .failure(error):
                print(error.localizedDescription)
            }
        }
        // 2.
        let starredParameters: Parameters = ["type": 2,
                                             "getRead": true,
                                             "batchSize": -1]
        
        let starredItemRouter = Router.items(parameters: starredParameters)
        session.request(starredItemRouter).responseDecodable(of: Items.self) { [weak self] response in
            switch response.result {
            case let .success(result):
                if let items = result.items {
                    CDItem.update(items: items, completion: nil)
                    self?.updateBadge()
                }
            case let .failure(error):
                print(error.localizedDescription)
            }
        }
        
        // 3.
        session.request(Router.folders).responseDecodable(of: Folders.self) { response in
            switch response.result {
            case let .success(result):
                if let folders = result.folders {
                    CDFolder.update(folders: folders)
                }
            case let .failure(error):
                print(error.localizedDescription)
            }
        }
        
        // 4.
        session.request(Router.feeds).responseDecodable(of: Feeds.self) { response in
            switch response.result {
            case let .success(result):
                if let newestItemId = result.newestItemId, let starredCount = result.starredCount {
                    CDFeeds.update(starredCount: starredCount, newestItemId: newestItemId)
                }
                if let feeds = response.value?.feeds {
                    CDFeed.update(feeds: feeds)
                }
            case let .failure(error):
                print(error.localizedDescription)
            }
        }
    }
    
    
    /*
     Syncing
     
     When syncing, you want to push read/unread and starred/unstarred items to the server and receive new and updated items, feeds and folders. To do that, call the following routes:
     
     1. Notify the News app of unread articles: PUT /items/unread/multiple {"items": [1, 3, 5] }
     2. Notify the News app of read articles: PUT /items/read/multiple {"items": [1, 3, 5]}
     3. Notify the News app of starred articles: PUT /items/starred/multiple {"items": [{"feedId": 3, "guidHash": "adadafasdasd1231"}, ...]}
     4. Notify the News app of unstarred articles: PUT /items/unstarred/multiple {"items": [{"feedId": 3, "guidHash": "adadafasdasd1231"}, ...]}
     5. Get new folders: GET /folders
     6. Get new feeds: GET /feeds
     7. Get new items and modified items: GET /items/updated?lastModified=12123123123&type=3
     
     */
    func sync(completion: @escaping SyncCompletionBlock) {
        guard let _ = CDItem.all() else {
            self.initialSync()
            return
        }
        
        //2
        func localRead(completion: @escaping SyncCompletionBlock) {
            if let localRead = CDRead.all(), localRead.count > 0 {
                let readParameters: Parameters = ["items": localRead]
                session.request(Router.itemsRead(parameters: readParameters)).responseData { response in
                    switch response.result {
                    case .success:
                        CDRead.clear()
                    case .failure(let error):
                        print(error.localizedDescription)
                    }
                    completion()
                }
            } else {
                completion()
            }
        }
        
        //3
        func localStarred(completion: @escaping SyncCompletionBlock) {
            if let localStarred = CDStarred.all(), localStarred.count > 0 {
                if let starredItems = CDItem.items(itemIds: localStarred) {
                    var params: [Any] = []
                    for starredItem in starredItems {
                        var param: [String: Any] = [:]
                        param["feedId"] = starredItem.feedId
                        param["guidHash"] = starredItem.guidHash
                        params.append(param)
                    }
                    let starredParameters: Parameters = ["items": params]
                    session.request(Router.itemsStarred(parameters: starredParameters)).responseData { response in
                        switch response.result {
                        case .success:
                            CDStarred.clear()
                        case .failure(let error):
                            print(error.localizedDescription)
                        }
                        completion()
                    }
                } else {
                    completion()
                }
            } else {
                completion()
            }
        }
        
        //4
        func localUnstarred(completion: @escaping SyncCompletionBlock) {
            if let localUnstarred = CDUnstarred.all(), localUnstarred.count > 0 {
                if let unstarredItems = CDItem.items(itemIds: localUnstarred) {
                    var params: [Any] = []
                    for unstarredItem in unstarredItems {
                        var param: [String: Any] = [:]
                        param["feedId"] = unstarredItem.feedId
                        param["guidHash"] = unstarredItem.guidHash
                        params.append(param)
                    }
                    let unstarredParameters: Parameters = ["items": params]
                    session.request(Router.itemsUnstarred(parameters: unstarredParameters)).responseData { response in
                        switch response.result {
                        case .success:
                            CDUnstarred.clear()
                        case .failure(let error):
                            print(error.localizedDescription)
                        }
                        completion()
                    }
                } else {
                    completion()
                }
            } else {
                completion()
            }
        }
        
        //5
        func folders(completion: @escaping SyncCompletionBlock) {
            session.request(Router.folders).responseDecodable(of: Folders.self) { [weak self] response in
                switch response.result {
                case let .success(result):
                    if let folders = result.folders {
                        var addedFolders = [FolderSync]()
                        var deletedFolders = [FolderSync]()
                        let ids = folders.map({ FolderSync.init(id: $0.id, name: $0.name ?? "Untitled") })
                        if let knownFolders = CDFolder.all() {
                            let knownIds = knownFolders.map({ FolderSync.init(id: $0.id, name: $0.name ?? "Untitled") })
                            addedFolders = ids.filter({
                                return !knownIds.contains($0)
                            })
                            deletedFolders = knownIds.filter({
                                return !ids.contains($0)
                            })
                        }
                        CDFolder.update(folders: folders)
                        NotificationCenter.default.post(name: .folderSync, object: self, userInfo: ["added": addedFolders, "deleted": deletedFolders])
                        CDFolder.delete(ids: deletedFolders.map( { $0.id }), in: NewsData.mainThreadContext)
                    }
                    completion()
                case let .failure(error):
                    print(error.localizedDescription)
                }
            }
        }
        
        //6
        func feeds(completion: @escaping SyncCompletionBlock) {
            session.request(Router.feeds).responseDecodable(of: Feeds.self) { [weak self] response in
                switch response.result {
                case let .success(result):
                    if let newestItemId = result.newestItemId, let starredCount = result.starredCount {
                        CDFeeds.update(starredCount: starredCount, newestItemId: newestItemId)
                    }
                    if let feeds = response.value?.feeds {
                        var addedFeeds = [FeedSync]()
                        var deletedFeeds = [FeedSync]()
                        let ids = feeds.map({ FeedSync.init(id: $0.id, title: $0.title ?? "Untitled", folderId: $0.folderId) })
                        if let knownFeeds = CDFeed.all() {
                            let knownIds = knownFeeds.map({ FeedSync.init(id: $0.id, title: $0.title ?? "Untitled", folderId: $0.folderId) })
                            addedFeeds = ids.filter({
                                return !knownIds.contains($0)
                            })
                            deletedFeeds = knownIds.filter({
                                return !ids.contains($0)
                            })
                        }
                        CDFeed.delete(ids: deletedFeeds.map( { $0.id }), in: NewsData.mainThreadContext)
                        if let allItems = CDItem.all() {
                            let deletedFeedItems = allItems.filter({
                                return deletedFeeds.map( { $0.id } ).contains($0.feedId) &&
                                    !addedFeeds.map( { $0.id }).contains($0.feedId)
                            })
                            let deletedFeedItemIds = deletedFeedItems.map({ $0.id })
                            CDItem.delete(ids: deletedFeedItemIds, in: NewsData.mainThreadContext)
                        }
                        CDFeed.update(feeds: feeds)
                        NotificationCenter.default.post(name: .feedSync, object: self, userInfo: ["added": addedFeeds, "deleted": deletedFeeds])
                    }
                    completion()
                case let .failure(error):
                    print(error.localizedDescription)
                }
            }
        }
        
        //7
        func items(completion: @escaping SyncCompletionBlock) {
            let updatedParameters: Parameters = ["type": 3,
                                                 "lastModified": CDItem.lastModified(),
                                                 "id": 0]
            
            let updatedItemRouter = Router.updatedItems(parameters: updatedParameters)
            session.request(updatedItemRouter).responseDecodable(of: Items.self) { response in
                switch response.result {
                case let .success(result):
                    if let items = result.items {
                        CDItem.update(items: items, completion: { (newItems) in
                            for newItem in newItems {
                                let feed = CDFeed.feed(id: newItem.feedId)
                                let notification = NSUserNotification()
                                notification.identifier = NSUUID().uuidString
                                notification.title = "CloudNews"
                                notification.subtitle = feed?.title ?? "New article"
                                notification.informativeText = newItem.title ?? ""
                                notification.soundName = NSUserNotificationDefaultSoundName
                                let notificationCenter = NSUserNotificationCenter.default
                                notificationCenter.deliver(notification)
                            }
                        })
                    }
                    completion()
                case let .failure(error):
                    print(error.localizedDescription)
                }
            }
        }
        
        localRead {
            localStarred {
                localUnstarred {
                    folders {
                        feeds {
                            items {
                                self.updateBadge()
                                completion()
                            }
                        }
                    }
                }
            }
        }
        
    }
    
    func updateBadge() {
        let unreadCount = CDItem.unreadCount()
        if unreadCount > 0 {
            NSApp.dockTile.badgeLabel = "\(unreadCount)"
        } else {
            NSApp.dockTile.badgeLabel = nil
        }
    }
    
}
