//
//  PringTests.swift
//  PringTests
//
//  Created by 1amageek on 2017/10/10.
//  Copyright © 2017年 Stamp Inc. All rights reserved.
//

import XCTest
@testable import Pring
import FirebaseFirestore
import FirebaseStorage
import FirebaseCore

class FirebaseTest {

    static let shared: FirebaseTest = FirebaseTest()

    init () {
        FirebaseApp.configure()
    }

}

class PringTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        _ = FirebaseTest.shared
    }

    func testCustomDocument() {
        let expectation: XCTestExpectation = XCTestExpectation()
        let document: CustomDocument = CustomDocument()
        document.save { _, _ in
            CustomDocument.get(document.id, block: { (document, _) in
                XCTAssertTrue(document!.reference.path.contains("custom"))
                XCTAssertTrue(document!.reference.path.contains("2"))
                document?.delete({ (_) in
                    CustomDocument.get(document!.id, block: { (document, _) in
                        XCTAssertNil(document)
                        expectation.fulfill()
                    })
                })
                expectation.fulfill()
            })
        }
        self.wait(for: [expectation], timeout: 10)
    }

    func testFiles() {
        let expectation: XCTestExpectation = XCTestExpectation(description: "Test Files")
        let document: MultipleFilesDocument = MultipleFilesDocument()

        document.file0 = File(data: UIImagePNGRepresentation(MultipleFilesDocument.image())!, mimeType: .png)
        document.file1 = File(data: UIImagePNGRepresentation(MultipleFilesDocument.image())!, mimeType: .png)
        document.file2 = File(data: UIImagePNGRepresentation(MultipleFilesDocument.image())!, mimeType: .png)

        let tasks = document.save { (ref, error) in
            MultipleFilesDocument.get(ref!.documentID, block: { (document, error) in
                XCTAssertNotNil(document)
                guard let document: MultipleFilesDocument = document else {
                    return
                }

                let ref0 = document.file0?.ref
                let ref1 = document.file1?.ref
                let ref2 = document.file2?.ref

                ref0?.getData(maxSize: 1000000, completion: { (data, error) in
                    XCTAssertNotNil(data)
                    ref1?.getData(maxSize: 1000000, completion: { (data, error) in
                        XCTAssertNotNil(data)
                        ref2?.getData(maxSize: 1000000, completion: { (data, error) in
                            XCTAssertNotNil(data)
                            document.file0 = File.delete()
                            document.file1 = File.delete()
                            document.file2 = File.delete()
                            document.update({ (error) in
                                MultipleFilesDocument.get(ref!.documentID, block: { (doc, error) in
                                    guard let doc: MultipleFilesDocument = doc else {
                                        return
                                    }
                                    XCTAssertNotNil(doc)
                                    XCTAssertNil(doc.file0)
                                    XCTAssertNil(doc.file1)
                                    XCTAssertNil(doc.file2)

                                    ref0?.getData(maxSize: 1000000, completion: { (data, error) in
                                        XCTAssertNil(data)
                                        ref1?.getData(maxSize: 1000000, completion: { (data, error) in
                                            XCTAssertNil(data)
                                            ref2?.getData(maxSize: 1000000, completion: { (data, error) in
                                                XCTAssertNil(data)
                                                expectation.fulfill()
                                            })
                                        })
                                    })
                                })
                            })
                        })
                    })
                })
            })
        }
        XCTAssertEqual(tasks.count, 3)
        self.wait(for: [expectation], timeout: 30)
    }

    func testNestedFiles() {
        let expectation: XCTestExpectation = XCTestExpectation(description: "Test Nested File delete")

        let document: MultipleFilesDocument = MultipleFilesDocument()
        let item: MultipleFilesNestedItem = MultipleFilesNestedItem()
        item.file = File(data: UIImagePNGRepresentation(MultipleFilesNestedItem.image())!, mimeType: .png)
        document.files.insert(item)
        let id: String = item.id

        document.save { (ref, error) in
            MultipleFilesDocument.get(ref!.documentID, block: { (document, error) in
                guard let document: MultipleFilesDocument = document else {
                    return
                }
                XCTAssertNotNil(document)
                document.files.get(id, block: { (item, error) in
                    let ref = item?.file?.ref
                    ref?.getData(maxSize: 1000000, completion: { (data, error) in
                        XCTAssertNotNil(data)
                        item?.file?.delete({ (error) in
                            ref?.getData(maxSize: 1000000, completion: { (data, error) in
                                XCTAssertNil(data)
                                expectation.fulfill()
                            })
                        })
                    })
                })
            })
        }

        self.wait(for: [expectation], timeout: 10)
    }

    func testMemory() {
        let expectation: XCTestExpectation = XCTestExpectation(description: "Test File")
        weak var weakDocument: TestDocument?

        do {
            let document: TestDocument = TestDocument()
            weakDocument = document
            document.save({ (ref, error) in
                TestDocument.get(ref!.documentID, block: { (document, error) in
                    let file1: File = File(data: UIImagePNGRepresentation(TestDocument.image1())!, mimeType: .png)
                    document?.file = file1
                    document?.update({ (error) in
                        TestDocument.get(ref!.documentID, block: { (document, error) in
                            expectation.fulfill()
                        })
                    })
                })
            })
        }

        self.wait(for: [expectation], timeout: 10)
        XCTAssertNil(weakDocument)
    }

    func testSubCollectionInsetBeforeSave() {
        let expectation: XCTestExpectation = XCTestExpectation(description: "Test SubCollection")
        let document: TestDocument = TestDocument()
        let nestedItem: NestedItem = NestedItem()
        document.subCollection.insert(nestedItem)
        document.save { (ref, error) in
            XCTAssertEqual(nestedItem.isSaved, true)
            XCTAssertEqual(document.isSaved, true)
            XCTAssertEqual(document.subCollection.first?.string, "nested")
            TestDocument.get(ref!.documentID, block: { (document, error) in
                document?.subCollection.get(nestedItem.id, block: { (item, error) in
                    XCTAssertEqual(item?.array.first, "nested")
                    XCTAssertEqual(item?.set.first, "nested")
                    XCTAssertEqual(item?.bool, true)
                    XCTAssertEqual(String(data: item!.binary, encoding: .utf8), "nested")
                    XCTAssertEqual(item?.url.absoluteString, "https://firebase.google.com/nested")
                    XCTAssertEqual(item?.int, Int.max)
                    XCTAssertEqual(item?.float, Double.infinity)
                    XCTAssertEqual(item?.date, Date(timeIntervalSince1970: 100))
                    XCTAssertEqual(item?.geoPoint, GeoPoint(latitude: 0, longitude: 0))
                    XCTAssertEqual(item?.dictionary.keys.first, "key")
                    XCTAssertEqual(item?.dictionary.values.first as! String, "nested")
                    XCTAssertEqual(item?.string, "nested")
                    expectation.fulfill()
                })
            })

        }
        self.wait(for: [expectation], timeout: 10)
    }

    func testSubCollectionInsetAfterSave() {
        let expectation: XCTestExpectation = XCTestExpectation(description: "Test SubCollection")
        let document: TestDocument = TestDocument()
        let nestedItem: NestedItem = NestedItem()
        document.save { (ref, error) in
            XCTAssertEqual(document.isSaved, true)
            document.subCollection.insert(nestedItem)
            document.update({ (error) in
                XCTAssertEqual(nestedItem.isSaved, true)
                XCTAssertEqual(document.subCollection.first?.string, "nested")
                TestDocument.get(ref!.documentID, block: { (document, error) in
                    document?.subCollection.get(nestedItem.id, block: { (item, error) in
                        XCTAssertEqual(item?.array.first, "nested")
                        XCTAssertEqual(item?.set.first, "nested")
                        XCTAssertEqual(item?.bool, true)
                        XCTAssertEqual(String(data: item!.binary, encoding: .utf8), "nested")
                        XCTAssertEqual(item?.url.absoluteString, "https://firebase.google.com/nested")
                        XCTAssertEqual(item?.int, Int.max)
                        XCTAssertEqual(item?.float, Double.infinity)
                        XCTAssertEqual(item?.date, Date(timeIntervalSince1970: 100))
                        XCTAssertEqual(item?.geoPoint, GeoPoint(latitude: 0, longitude: 0))
                        XCTAssertEqual(item?.dictionary.keys.first, "key")
                        XCTAssertEqual(item?.dictionary.values.first as! String, "nested")
                        XCTAssertEqual(item?.string, "nested")
                        expectation.fulfill()
                    })
                })
            })
        }
        self.wait(for: [expectation], timeout: 10)
    }

    var dataSource: DataSource<DataSourceItem>?

    func testDataSource() {
        let expectation: XCTestExpectation = XCTestExpectation(description: "Test DataSource")

        let group: DispatchGroup = DispatchGroup()
        let queue: DispatchQueue = DispatchQueue(label: "Dispatch.Queue")
        let count: Int = 10
        queue.async {
            (0..<count).forEach({ (index) in
                group.enter()
                let document: DataSourceItem = DataSourceItem()
                document.index = index
                document.save({ (ref, error) in
                    group.leave()
                })
            })
            group.notify(queue: .main, execute: {
                self.dataSource = DataSourceItem.query.dataSource().on({ (snapshot, change) in
                    switch change {
                    case .update(deletions: _, insertions: let insertions, modifications: _):
                        XCTAssertEqual(insertions.count, 1)
                    default: break
                    }
                }).onCompleted({ (snapshot, items) in
                    XCTAssertEqual(snapshot?.count, count)
                    items.forEach({ (item) in
                        item.delete()
                    })
                    expectation.fulfill()
                }).get()
            })
            group.wait()
        }
        self.wait(for: [expectation], timeout: 20)
    }

    func testReferenceCollection() {
        let expectation: XCTestExpectation = XCTestExpectation(description: "Test ReferenceCollection")
        let object: CollectionObject = CollectionObject()

        object.save { (ref, _) in
            CollectionObject.get(ref!.documentID, block: { (object, _) in
                let obj: CollectionObject = CollectionObject()
                object?.referenceCollection.insert(obj)
                object?.update({ (_) in
                    CollectionObject.get(ref!.documentID, block: { (object, _) in
                        guard let object: CollectionObject = object else {
                            return
                        }
                        object.referenceCollection.query.dataSource().onCompleted({ (_, items) in
                            XCTAssertEqual(items.count, 1)
                            expectation.fulfill()
                        }).get()
                    })
                })
            })
        }
        self.wait(for: [expectation], timeout: 20)
    }
}
