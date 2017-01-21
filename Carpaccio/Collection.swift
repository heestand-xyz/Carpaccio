//
//  ImageCollection.swift
//  Trimmer
//
//  Created by Matias Piipari on 07/05/2016.
//  Copyright © 2016 Matias Piipari & Co. All rights reserved.
//

import Foundation

public protocol ImageCollection: class
{
    var images: AnyCollection<Image> { get }
    var imageCount: Int { get }
    var imageURLs: AnyCollection<URL> { get }
    var name: String { get }
    var URL: Foundation.URL? { get }
    
    func contains(image: Image) -> Bool
}

extension Carpaccio.Collection: ImageCollection
{
    public func contains(image: Image) -> Bool {
        return self.images.contains(image)
    }
    
    public var imageURLs: AnyCollection<URL> {
        get {
            return AnyCollection<URL>(self.images.lazy.flatMap { image in
                return image.URL
            })
        }
    }
}

public typealias CollectionImageBatchHandler = (_ preparedBatchOfImages: [Image]) -> Void
public typealias CollectionCompletionHandler = (_ completedCollection: Collection) -> Void
public typealias CollectionErrorHandler = (_ error: Error) -> Void

open class Collection
{
    public var images: AnyCollection<Image>
    public let name: String

    public var imageCount: Int {
        return Int(self.images.count)
    }
    
    public let sortingScheme: SortingScheme
    public let URL: Foundation.URL?
    
    public init(url: URL, sortingScheme: SortingScheme) {
        self.URL = url
        self.name = url.lastPathComponent
        self.sortingScheme = sortingScheme
        self.images = AnyCollection<Image>([Image]())
    }
    
    public required init(name: String, images: AnyCollection<Image>, imageCount: Int, URL: Foundation.URL) throws
    {
        self.URL = URL
        self.name = name
        self.images = images
        self.sortingScheme = .none
    }
    
    public init(contentsOfURL URL: Foundation.URL) throws {
        self.URL = URL
        self.name = URL.lastPathComponent
        
        let (images, _) = try Collection.load(contentsOfURL: URL)
        self.images = AnyCollection<Image>(images)
        self.sortingScheme = .none
    }
    
    public enum SortingScheme {
        case none
        case byName
    }
    
    class func imageURLs(atCollectionURL URL: URL) throws -> [URL]
    {
        let fileManager = FileManager.default
        let path = URL.path
        
        guard let enumerator = fileManager.enumerator(atPath: path) else {
            throw Image.Error.locationNotEnumerable(URL)
        }
        
        let urls = enumerator.lazy.map { anyPath -> Foundation.URL in
            let path = anyPath as! String
            let url = URL.appendingPathComponent(path, isDirectory: false).absoluteURL
            return url
            }.filter { url in
                if let attributes = enumerator.fileAttributes, attributes[.type] as! FileAttributeType == .typeRegular {
                    let pathExtension = (url.lastPathComponent as NSString).pathExtension.lowercased()
                    return Image.imageFileExtensions.contains(pathExtension)
                }
                return false
        }
        
        return urls
    }
    
    /** Asynchronously initialise an image collection rooted at given URL, with all images found in the subtree prepared up to essential metadata having been loaded. */
    public class func prepare(atURL collectionURL: URL,
                              queue: DispatchQueue = DispatchQueue.global(),
                              sortingScheme: SortingScheme = .none,
                              maxMetadataLoadParallelism: Int? = nil,
                              completionHandler: @escaping CollectionCompletionHandler,
                              errorHandler: @escaping CollectionErrorHandler) {
        queue.async {
            do {
                let imageURLs = try self.imageURLs(atCollectionURL: collectionURL)
                
                let images = imageURLs.lazy.parallelFlatMap(maxParallelism:maxMetadataLoadParallelism) { URL -> Image? in
                    do {
                        let image = try Image(URL: URL)
                        image.fetchMetadata()
                        return image
                    }
                    catch {
                        print("ERROR! Failed to load image at '\(URL.path)'")
                        return nil
                    }
                }
                
                let returnedImages:AnyCollection<Image>
                
                switch sortingScheme {
                case .none:
                    returnedImages = AnyCollection<Image>(images)
                    
                case .byName:
                    returnedImages = AnyCollection<Image>(images.sorted { image1, image2 in
                        return image1.name.compare(image2.name) == .orderedAscending
                    })
                }
                
                let collection = try self.init(name: collectionURL.lastPathComponent,
                                               images: returnedImages,
                                               imageCount: imageURLs.count,
                                               URL: collectionURL)
                completionHandler(collection)
            }
            catch {
                errorHandler(Image.Error.loadingFailed(underlyingError: error))
            }
        }
    }
    
    // MARK: Batched image discovery
    public func prepare(batchSize: Int = 50, maximumParallelism: Int = 1, batchHandler: @escaping CollectionImageBatchHandler, completionHandler: @escaping CollectionCompletionHandler,  errorHandler: @escaping CollectionErrorHandler) {
        guard let url = self.URL else {
            return
        }
        
        do {
            let urls = try Collection.imageURLs(atCollectionURL: url)
            print("Will prepare \(urls.count) source images at \(url.path)")
            prepareNextBatch(ofImageURLs: urls, startingAt: 0, batchSize: batchSize, maximumParallelism: maximumParallelism, batchHandler: batchHandler, completionHandler: completionHandler)
        } catch {
            errorHandler(error)
        }
    }
    
    private lazy var prepareOperationQueue: OperationQueue = {
        let opq = OperationQueue()
        opq.maxConcurrentOperationCount = 1
        return opq
    }()
    
    private func prepareNextBatch(ofImageURLs urls: [URL], startingAt firstIndex: Int, batchSize n: Int, maximumParallelism: Int, batchHandler: @escaping CollectionImageBatchHandler, completionHandler: @escaping CollectionCompletionHandler) {
        let lastIndex = min(firstIndex + n - 1, urls.count - 1)
        
        guard firstIndex < urls.endIndex, lastIndex >= firstIndex else {
            completionHandler(self)
            return
        }
        
        weak var weakCollection = self
        
        prepareOperationQueue.addOperation {
            guard let collection = weakCollection else {
                return
            }
            
            print("Will prepare next batch of max \(n) images (out of \(urls.count)), \(firstIndex) ... \(lastIndex)")
            
            let preparedBatchOfImages = Array(urls[firstIndex ... lastIndex]).lazy.parallelFlatMap(maxParallelism: maximumParallelism) { url -> Image? in
                do {
                    let image = try Image(URL: url)
                    image.fetchMetadata()
                    return image
                }
                catch {
                    print("ERROR! Failed to initialise image at '\(url.path)'")
                    return nil
                }
            }
            
            collection.images = AnyCollection<Image>([collection.images, AnyCollection<Image>(preparedBatchOfImages)].joined())
            batchHandler(preparedBatchOfImages)

            collection.prepareNextBatch(ofImageURLs: urls, startingAt: firstIndex + n, batchSize: n, maximumParallelism: maximumParallelism, batchHandler: batchHandler, completionHandler: completionHandler)
        }
    }
    
    // MARK: Image loading
    public typealias ImageLoadHandler = (_ index:Int, _ total:Int, _ image:Image) -> Void
    public typealias ImageLoadErrorHandler = (Error) -> Void
    
    public class func load(contentsOfURL URL: Foundation.URL, loadHandler: ImageLoadHandler? = nil) throws -> (AnyCollection<Image>, Int)
    {
        let imageURLs = try Collection.imageURLs(atCollectionURL: URL)
        let count = imageURLs.count
        
        let images = try imageURLs.lazy.enumerated().flatMap { (i, imageURL) -> Image? in
            let pathExtension = imageURL.pathExtension
            
            guard pathExtension.utf8.count > 0 else {
                return nil
            }
            
            let image = try Image(URL: imageURL)
            loadHandler?(i, imageURLs.count, image)
            
            return image
        }
        
        let imageCollection = AnyCollection<Image>(images)
        return (imageCollection, count)
    }
    
    public class func loadAsynchronously(contentsOfURL URL:Foundation.URL, queue:DispatchQueue = DispatchQueue.global(), loadHandler: ImageLoadHandler? = nil, errorHandler:@escaping ImageLoadErrorHandler) {
        queue.async {
            do {
                _ = try load(contentsOfURL: URL, loadHandler: loadHandler)
            }
            catch {
                errorHandler(Image.Error.loadingFailed(underlyingError: error))
            }
        }
    }
    
    /** Return any image found in this collection whose URL is included in given input array or URLs. */
    public func images(forURLs URLs: [Foundation.URL]) -> [Image]
    {
        var images = [Image]()
        
        for URL in URLs
        {
            if let i = self.images.index( where: { (image: Image) -> Bool in
                return image.URL == URL
            }) {
                images.append(self.images[i])
            }
        }
        
        return images
    }
    
    // TODO: Create a specific type for a sparse distance matrix.
    public func distanceMatrix(_ distance:Image.DistanceFunction) -> [[Double]] {
        return images.indices.lazy.flatMap { i in
            var row = [Double]()
            for e in images.indices {
                if e == i {
                    row.append(0)
                }
                else {
                    row.append(Double.nan)
                }
            }
            
            let iSuccessor = self.images.indices.index(after: i)
            for j in (self.images.indices.suffix(from: iSuccessor)) {
                let col = self.images.indices.distance(from: self.images.indices.startIndex, to: j)
                row[col] = distance(images[i], images[j])
            }

            return row
        }
    }
    
    // TODO: Use a Swot data frame as return type instead?
    public func distanceTable(_ distance:Image.DistanceFunction) -> [[Double]] {
        let distMatrix = self.distanceMatrix(distance)
        
        if (distMatrix.count == 0) { return [[Double]]() }
        
        return images.indices.map { i in
            let iDist = images.indices.distance(from: images.indices.startIndex, to: i)
            
            return images.indices.map { j in
                let jDist = images.indices.distance(from: images.indices.startIndex, to: j)
            
                if j < i {
                    return distMatrix[jDist][iDist]
                }
                
                return distMatrix[iDist][jDist]
            }
        }
    }
        
}
