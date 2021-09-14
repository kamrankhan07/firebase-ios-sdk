/*
 * Copyright 2021 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import SwiftUI
import FirebaseFirestore

@available(iOS 14.0, macOS 11.0, macCatalyst 14.0, tvOS 14.0, watchOS 7.0, *)
internal class FirestoreQueryObservable<T>: ObservableObject {
  @Published var items: T

  private let firestore = Firestore.firestore()
  private var listener: ListenerRegistration?

  private var setupListener: (() -> Void)!

  internal var preventUpdates = false
  internal var configuration: FirestoreQuery<T>.Configuration {
    didSet {
      if !preventUpdates {
        removeListener()
        setupListener()
      }
    }
  }

  init<U: Decodable>(configuration: FirestoreQuery<T>.Configuration) where T == [U] {
    items = []
    self.configuration = configuration
    setupListener = createListener { [weak self] querySnapshot, error in
      if let error = error {
        self?.items = []
        self?.projectError(error)
        return
      }

      guard let documents = querySnapshot?.documents else {
        self?.items = []
        return
      }

      self?.projectError(nil)

      let decodedDocuments: [U] = documents.compactMap { queryDocumentSnapshot in
        let result = Result { try queryDocumentSnapshot.data(as: U.self) }
        switch result {
        case let .success(decodedDocument):
          return decodedDocument
        case let .failure(error):
          self?.projectError(error)
          return nil
        }
      }

      if self?.configuration.error != nil {
        if configuration.decodingFailureStrategy == .raise {
          self?.items = []
        } else {
          self?.items = decodedDocuments
        }
      } else {
        self?.items = decodedDocuments
      }
    }

    setupListener()
  }

  init<U: Decodable>(configuration: FirestoreQuery<T>.Configuration) where T == Result<[U], Error> {
    items = .success([])
    self.configuration = configuration
    setupListener = createListener { [weak self] querySnapshot, error in
      if let error = error {
        self?.items = .failure(error)
        self?.projectError(error)
        return
      }

      guard let documents = querySnapshot?.documents else {
        self?.items = .success([])
        return
      }

      self?.projectError(nil)

      let decodedDocuments: [U] = documents.compactMap { queryDocumentSnapshot in
        let result = Result { try queryDocumentSnapshot.data(as: U.self) }
        switch result {
        case let .success(decodedDocument):
          return decodedDocument
        case let .failure(error):
          self?.projectError(error)
          return nil
        }
      }

      if let error = self?.configuration.error {
        if configuration.decodingFailureStrategy == .raise {
          self?.items = .failure(error)
        } else {
          self?.items = .success(decodedDocuments)
        }
      } else {
        self?.items = .success(decodedDocuments)
      }
    }

    setupListener()
  }

  deinit {
    removeListener()
  }

  private func createListener(with handler: @escaping (QuerySnapshot?, Error?) -> Void)
    -> () -> Void {
    return {
      var query: Query = self.firestore.collection(self.configuration.path)

      for predicate in self.configuration.predicates {
        switch predicate {
        case let .isEqualTo(field, value):
          query = query.whereField(field, isEqualTo: value)
        case let .isIn(field, values):
          query = query.whereField(field, in: values)
        case let .isNotIn(field, values):
          query = query.whereField(field, notIn: values)
        case let .arrayContains(field, value):
          query = query.whereField(field, arrayContains: value)
        case let .arrayContainsAny(field, values):
          query = query.whereField(field, arrayContainsAny: values)
        case let .isLessThan(field, value):
          query = query.whereField(field, isLessThan: value)
        case let .isGreaterThan(field, value):
          query = query.whereField(field, isGreaterThan: value)
        case let .isLessThanOrEqualTo(field, value):
          query = query.whereField(field, isLessThanOrEqualTo: value)
        case let .isGreaterThanOrEqualTo(field, value):
          query = query.whereField(field, isGreaterThanOrEqualTo: value)
        case let .orderBy(field, value):
          query = query.order(by: field, descending: value)
        case let .limitTo(field):
          query = query.limit(to: field)
        case let .limitToLast(field):
          query = query.limit(toLast: field)
        }
      }

      self.listener = query.addSnapshotListener(handler)
    }
  }

  private func projectError(_ error: Error?) {
    preventUpdates = true
    configuration.error = error
    preventUpdates = false
  }

  private func removeListener() {
    listener?.remove()
    listener = nil
  }
}
