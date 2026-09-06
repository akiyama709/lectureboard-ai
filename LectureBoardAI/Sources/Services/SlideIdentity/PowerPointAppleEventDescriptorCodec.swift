import ApplicationServices
import Foundation

enum PowerPointAppleEventCode {
  static let activePresentation: OSType = 0x4141_5072  // AAPr
  static let presentation: OSType = 0x7070_7450  // pptP
  static let slideShowSettings: OSType = 0x5353_5374  // SSSt
  static let slideShowWindow: OSType = 0x7053_5377  // pSSw
  static let slideShowView: OSType = 0x5053_5376  // PSSv
  static let slide: OSType = 0x7053_4C44  // pSLD
  static let slideState: OSType = 0x5373_5465  // SsTe
  static let slideID: OSType = 0x536C_4944  // SlID
  static let slideIndex: OSType = 0x5349_6458  // SIdX
  static let presentationSaved: OSType = 0x7361_7665  // save
  static let visible: OSType = 0x7076_6973  // pvis
  static let slideShowType: OSType = 0x5377_5479  // SwTy
  static let powerPointSuite: OSType = 0x7350_5054  // sPPT
  static let runSlideShow: OSType = 0x5253_7348  // RSsH
  static let exitSlideShow: OSType = 0x7853_7377  // xSsw
  static let running: OSType = 0x00D3_0001
  static let black: OSType = 0x00D3_0003
  static let white: OSType = 0x00D3_0004
}

enum PowerPointAppleEventObjectClass: OSType, CaseIterable {
  case presentation = 0x7070_7450
  case slideShowSettings = 0x5353_5374
  case slideShowWindow = 0x7053_5377
  case slideShowView = 0x5053_5376
  case slide = 0x7053_4C44
}

enum PowerPointAppleEventProperty: OSType, CaseIterable {
  case activePresentation = 0x4141_5072
  case presentation = 0x7070_7450
  case slideShowSettings = 0x5353_5374
  case slideShowWindow = 0x7053_5377
  case slideShowView = 0x5053_5376
  case slide = 0x7053_4C44
  case slideState = 0x5373_5465
  case slideID = 0x536C_4944
  case slideIndex = 0x5349_6458
  case presentationSaved = 0x7361_7665
  case visible = 0x7076_6973
  case slideShowType = 0x5377_5479
}

/// Values from PowerPoint's `EPPSlideShowType` terminology.  Managed v1 starts only a windowed
/// show: fullscreen/speaker, kiosk, and presenter modes can move the editing window to another
/// Space and cannot satisfy the exact-window capture boundary.
enum PowerPointSlideShowType: OSType, CaseIterable, Equatable {
  case speaker = 0x00D5_0001
  case window = 0x00D5_0002
  case kiosk = 0x00D5_0003
  case presenter = 0x00D5_0005
}

enum PowerPointSlideShowState: OSType, CaseIterable, Equatable {
  case running = 0x00D3_0001
  case black = 0x00D3_0003
  case white = 0x00D3_0004
}

enum PowerPointAppleEventBoundedError: Equatable {
  case wouldRequireUserConsent
  case notPermitted
  case targetNotRunning
  case timedOut
  case unsupportedOperation
  case other
}

enum PowerPointAppleEventReplyFailure: Equatable {
  case missingReply
  case malformedReply
  case appleEventError(PowerPointAppleEventBoundedError)
  case missingDirectParameter
  case unexpectedDirectParameterType
  case unsupportedSlideShowState
  case unsupportedSlideShowType
  case malformedObjectSpecifier
}

enum PowerPointAppleEventParsed<Value> {
  case value(Value)
  case failure(PowerPointAppleEventReplyFailure)
}

/// Runtime-only ownership of a live object specifier returned by PowerPoint.
///
/// This deliberately has no `Sendable`, `Codable`, hashing, or textual representation. It must
/// remain inside the live client actor that owns the codec and must never become a persisted or
/// logged token.
final class PowerPointAppleEventRuntimeObjectSpecifier {
  fileprivate let descriptor: NSAppleEventDescriptor

  fileprivate init?(copying descriptor: NSAppleEventDescriptor) {
    guard let copy = descriptor.copy() as? NSAppleEventDescriptor else { return nil }
    self.descriptor = copy
  }
}

/// Synchronous descriptor builder/parser intended to be owned and used by one live client actor.
///
/// `NSAppleEventDescriptor` is intentionally not made `Sendable`. This helper never sends an event;
/// the future live client must keep every descriptor and parsed runtime object on its own actor.
final class PowerPointAppleEventDescriptorCodec {
  static let sendOptions = NSAppleEventDescriptor.SendOptions(
    rawValue: UInt(kAEWaitReply | kAENeverInteract | kAEDoNotPromptForUserConsent)
  )

  /// Limits apply before an untrusted reply descriptor is retained as a live runtime reference.
  /// They are deliberately small because the supported PowerPoint object paths have at most four
  /// nested object specifiers and no supported selector needs a large payload.
  private static let maximumRuntimeObjectSpecifierDepth = 4
  private static let maximumRuntimeObjectSpecifierBytes = 8_192
  private static let maximumRuntimeNameUTF16Length = 1_024
  private static let requiredObjectSpecifierFieldCount = 4

  func targetDescriptor(processIdentifier: Int32) -> NSAppleEventDescriptor? {
    guard processIdentifier > 0 else { return nil }
    return NSAppleEventDescriptor(processIdentifier: pid_t(processIdentifier))
  }

  func rootPropertySpecifier(
    _ property: PowerPointAppleEventProperty
  ) -> NSAppleEventDescriptor? {
    propertySpecifier(property, of: NSAppleEventDescriptor.null())
  }

  func nestedPropertySpecifier(
    _ properties: [PowerPointAppleEventProperty]
  ) -> NSAppleEventDescriptor? {
    guard (1...8).contains(properties.count) else { return nil }
    var container = NSAppleEventDescriptor.null()
    for property in properties {
      guard let next = propertySpecifier(property, of: container) else { return nil }
      container = next
    }
    return container
  }

  func propertySpecifier(
    _ property: PowerPointAppleEventProperty,
    of container: PowerPointAppleEventRuntimeObjectSpecifier
  ) -> NSAppleEventDescriptor? {
    propertySpecifier(property, of: container.descriptor)
  }

  /// Builds a property path rooted only in an already retained runtime object.
  ///
  /// This deliberately accepts no title, index, geometry, or application-root fallback. The
  /// returned path therefore continues to address the exact object returned by `run slide show`.
  func nestedPropertySpecifier(
    _ properties: [PowerPointAppleEventProperty],
    of container: PowerPointAppleEventRuntimeObjectSpecifier
  ) -> NSAppleEventDescriptor? {
    guard (1...8).contains(properties.count) else { return nil }
    var descriptor = container.descriptor
    for property in properties {
      guard let next = propertySpecifier(property, of: descriptor) else { return nil }
      descriptor = next
    }
    return descriptor
  }

  /// Builds one of the two supported pre-start paths from the active-presentation reply.
  ///
  /// PowerPoint may return its root active-presentation property as a presentation-class alias
  /// (`pptP/prop/AAPr/null`) which it accepts as a reply value but does not resolve when that raw
  /// value is sent back as a container. Only that exact alias is replaced with the canonical
  /// application-root property (`prop/prop/AAPr/null`). All other valid presentation references
  /// remain byte-for-byte the retained root, and this normalization is never available for a
  /// returned slide-show object.
  func preStartPresentationPropertySpecifier(
    _ properties: [PowerPointAppleEventProperty],
    of activePresentation: PowerPointAppleEventRuntimeObjectSpecifier
  ) -> NSAppleEventDescriptor? {
    guard
      properties == [.slideShowSettings]
        || properties == [.slideShowSettings, .slideShowType],
      Self.isValidRuntimeObjectSpecifier(
        activePresentation.descriptor,
        expectedClass: .presentation,
        depth: 1
      )
    else { return nil }

    let retained = activePresentation.descriptor
    let root: NSAppleEventDescriptor
    if Self.isExactRootActivePresentationAlias(retained) {
      guard let canonical = rootPropertySpecifier(.activePresentation) else { return nil }
      root = canonical
    } else {
      root = retained
    }

    var descriptor = root
    for property in properties {
      guard let next = propertySpecifier(property, of: descriptor) else { return nil }
      descriptor = next
    }
    return descriptor
  }

  func elementSpecifier(
    _ objectClass: PowerPointAppleEventObjectClass,
    at index: Int32,
    in container: NSAppleEventDescriptor
  ) -> NSAppleEventDescriptor? {
    guard index > 0, Self.isContainer(container) else { return nil }
    return objectSpecifier(
      desiredClass: objectClass.rawValue,
      keyForm: OSType(formAbsolutePosition),
      keyData: NSAppleEventDescriptor(int32: index),
      container: container
    )
  }

  func getEvent(
    processIdentifier: Int32,
    object: NSAppleEventDescriptor
  ) -> NSAppleEventDescriptor? {
    coreEvent(
      processIdentifier: processIdentifier,
      eventID: AEEventID(kAEGetData),
      directObject: object
    )
  }

  func countEvent(
    processIdentifier: Int32,
    objectClass: PowerPointAppleEventObjectClass,
    in container: NSAppleEventDescriptor
  ) -> NSAppleEventDescriptor? {
    guard
      let event = coreEvent(
        processIdentifier: processIdentifier,
        eventID: AEEventID(kAECountElements),
        directObject: container,
        acceptsNullDirectObject: true
      )
    else { return nil }
    event.setParam(
      NSAppleEventDescriptor(typeCode: objectClass.rawValue),
      forKeyword: AEKeyword(keyAEObjectClass)
    )
    return event
  }

  func setBooleanEvent(
    processIdentifier: Int32,
    object: NSAppleEventDescriptor,
    value: Bool
  ) -> NSAppleEventDescriptor? {
    setEvent(
      processIdentifier: processIdentifier,
      object: object,
      value: NSAppleEventDescriptor(boolean: value)
    )
  }

  func setSlideShowStateEvent(
    processIdentifier: Int32,
    object: NSAppleEventDescriptor,
    value: PowerPointSlideShowState
  ) -> NSAppleEventDescriptor? {
    setEvent(
      processIdentifier: processIdentifier,
      object: object,
      value: NSAppleEventDescriptor(enumCode: value.rawValue)
    )
  }

  func runSlideShowEvent(
    processIdentifier: Int32,
    settings: NSAppleEventDescriptor
  ) -> NSAppleEventDescriptor? {
    guard
      settings.descriptorType == DescType(typeObjectSpecifier),
      let target = targetDescriptor(processIdentifier: processIdentifier)
    else { return nil }
    let event = NSAppleEventDescriptor(
      eventClass: AEEventClass(PowerPointAppleEventCode.powerPointSuite),
      eventID: AEEventID(PowerPointAppleEventCode.runSlideShow),
      targetDescriptor: target,
      returnID: AEReturnID(kAutoGenerateReturnID),
      transactionID: AETransactionID(kAnyTransactionID)
    )
    event.setParam(settings, forKeyword: AEKeyword(keyDirectObject))
    return event
  }

  /// Addresses the view belonging to the exact returned slide-show object and exits that view.
  func exitSlideShowEvent(
    processIdentifier: Int32,
    slideShowWindow: PowerPointAppleEventRuntimeObjectSpecifier
  ) -> NSAppleEventDescriptor? {
    guard
      let view = nestedPropertySpecifier([.slideShowView], of: slideShowWindow)
    else { return nil }
    return powerPointEvent(
      processIdentifier: processIdentifier,
      eventID: AEEventID(PowerPointAppleEventCode.exitSlideShow),
      directObject: view
    )
  }

  func parseInt32Reply(
    _ reply: NSAppleEventDescriptor?
  ) -> PowerPointAppleEventParsed<Int32> {
    parseDirectParameter(reply, expectedType: DescType(typeSInt32)) { $0.int32Value }
  }

  func parseBooleanReply(
    _ reply: NSAppleEventDescriptor?
  ) -> PowerPointAppleEventParsed<Bool> {
    parseDirectParameter(reply, expectedType: DescType(typeBoolean)) { $0.booleanValue }
  }

  func parseSlideShowStateReply(
    _ reply: NSAppleEventDescriptor?
  ) -> PowerPointAppleEventParsed<PowerPointSlideShowState> {
    switch directParameter(reply, expectedType: DescType(typeEnumerated)) {
    case .failure(let failure):
      return .failure(failure)
    case .value(let descriptor):
      guard let state = PowerPointSlideShowState(rawValue: descriptor.enumCodeValue) else {
        return .failure(.unsupportedSlideShowState)
      }
      return .value(state)
    }
  }

  func parseSlideShowTypeReply(
    _ reply: NSAppleEventDescriptor?
  ) -> PowerPointAppleEventParsed<PowerPointSlideShowType> {
    switch directParameter(reply, expectedType: DescType(typeEnumerated)) {
    case .failure(let failure):
      return .failure(failure)
    case .value(let descriptor):
      guard let type = PowerPointSlideShowType(rawValue: descriptor.enumCodeValue) else {
        return .failure(.unsupportedSlideShowType)
      }
      return .value(type)
    }
  }

  /// Parses a successful command reply that must not carry an application value.
  func parseCommandReply(
    _ reply: NSAppleEventDescriptor?
  ) -> PowerPointAppleEventParsed<Void> {
    switch validateReply(reply) {
    case .failure(let failure):
      return .failure(failure)
    case .value(let reply):
      if let direct = reply.paramDescriptor(forKeyword: AEKeyword(keyDirectObject)),
        direct.descriptorType != DescType(typeNull)
      {
        return .failure(.unexpectedDirectParameterType)
      }
      return .value(())
    }
  }

  func parseObjectSpecifierReply(
    _ reply: NSAppleEventDescriptor?,
    expectedClass: PowerPointAppleEventObjectClass
  ) -> PowerPointAppleEventParsed<PowerPointAppleEventRuntimeObjectSpecifier> {
    switch directParameter(reply, expectedType: DescType(typeObjectSpecifier)) {
    case .failure(let failure):
      return .failure(failure)
    case .value(let descriptor):
      guard
        Self.isValidRuntimeObjectSpecifier(
          descriptor,
          expectedClass: expectedClass,
          depth: 1
        ),
        let runtimeObject = PowerPointAppleEventRuntimeObjectSpecifier(copying: descriptor)
      else { return .failure(.malformedObjectSpecifier) }
      return .value(runtimeObject)
    }
  }

  private func propertySpecifier(
    _ property: PowerPointAppleEventProperty,
    of container: NSAppleEventDescriptor
  ) -> NSAppleEventDescriptor? {
    guard Self.isContainer(container) else { return nil }
    return objectSpecifier(
      desiredClass: OSType(typeProperty),
      keyForm: OSType(formPropertyID),
      keyData: NSAppleEventDescriptor(typeCode: property.rawValue),
      container: container
    )
  }

  private func objectSpecifier(
    desiredClass: OSType,
    keyForm: OSType,
    keyData: NSAppleEventDescriptor,
    container: NSAppleEventDescriptor
  ) -> NSAppleEventDescriptor? {
    let record = NSAppleEventDescriptor.record()
    record.setDescriptor(
      NSAppleEventDescriptor(typeCode: desiredClass),
      forKeyword: AEKeyword(keyAEDesiredClass)
    )
    record.setDescriptor(
      NSAppleEventDescriptor(enumCode: keyForm),
      forKeyword: AEKeyword(keyAEKeyForm)
    )
    record.setDescriptor(keyData, forKeyword: AEKeyword(keyAEKeyData))
    record.setDescriptor(container, forKeyword: AEKeyword(keyAEContainer))
    return record.coerce(toDescriptorType: DescType(typeObjectSpecifier))
  }

  private func coreEvent(
    processIdentifier: Int32,
    eventID: AEEventID,
    directObject: NSAppleEventDescriptor,
    acceptsNullDirectObject: Bool = false
  ) -> NSAppleEventDescriptor? {
    guard
      (acceptsNullDirectObject && directObject.descriptorType == DescType(typeNull))
        || directObject.descriptorType == DescType(typeObjectSpecifier),
      let target = targetDescriptor(processIdentifier: processIdentifier)
    else { return nil }
    let event = NSAppleEventDescriptor(
      eventClass: AEEventClass(kAECoreSuite),
      eventID: eventID,
      targetDescriptor: target,
      returnID: AEReturnID(kAutoGenerateReturnID),
      transactionID: AETransactionID(kAnyTransactionID)
    )
    event.setParam(directObject, forKeyword: AEKeyword(keyDirectObject))
    return event
  }

  private func powerPointEvent(
    processIdentifier: Int32,
    eventID: AEEventID,
    directObject: NSAppleEventDescriptor
  ) -> NSAppleEventDescriptor? {
    guard directObject.descriptorType == DescType(typeObjectSpecifier),
      let target = targetDescriptor(processIdentifier: processIdentifier)
    else { return nil }
    let event = NSAppleEventDescriptor(
      eventClass: AEEventClass(PowerPointAppleEventCode.powerPointSuite),
      eventID: eventID,
      targetDescriptor: target,
      returnID: AEReturnID(kAutoGenerateReturnID),
      transactionID: AETransactionID(kAnyTransactionID)
    )
    event.setParam(directObject, forKeyword: AEKeyword(keyDirectObject))
    return event
  }

  private func setEvent(
    processIdentifier: Int32,
    object: NSAppleEventDescriptor,
    value: NSAppleEventDescriptor
  ) -> NSAppleEventDescriptor? {
    guard
      let event = coreEvent(
        processIdentifier: processIdentifier,
        eventID: AEEventID(kAESetData),
        directObject: object
      )
    else { return nil }
    event.setParam(value, forKeyword: AEKeyword(keyAEData))
    return event
  }

  private func parseDirectParameter<Value>(
    _ reply: NSAppleEventDescriptor?,
    expectedType: DescType,
    transform: (NSAppleEventDescriptor) -> Value
  ) -> PowerPointAppleEventParsed<Value> {
    switch directParameter(reply, expectedType: expectedType) {
    case .failure(let failure):
      return .failure(failure)
    case .value(let descriptor):
      return .value(transform(descriptor))
    }
  }

  private func directParameter(
    _ reply: NSAppleEventDescriptor?,
    expectedType: DescType
  ) -> PowerPointAppleEventParsed<NSAppleEventDescriptor> {
    switch validateReply(reply) {
    case .failure(let failure):
      return .failure(failure)
    case .value(let validatedReply):
      guard
        let direct = validatedReply.paramDescriptor(
          forKeyword: AEKeyword(keyDirectObject)
        )
      else {
        return .failure(.missingDirectParameter)
      }
      guard direct.descriptorType == expectedType else {
        return .failure(.unexpectedDirectParameterType)
      }
      return .value(direct)
    }
  }

  private func validateReply(
    _ reply: NSAppleEventDescriptor?
  ) -> PowerPointAppleEventParsed<NSAppleEventDescriptor> {
    guard let reply else { return .failure(.missingReply) }
    guard
      reply.descriptorType == DescType(typeAppleEvent),
      reply.eventClass == AEEventClass(kCoreEventClass),
      reply.eventID == AEEventID(kAEAnswer)
    else { return .failure(.malformedReply) }
    if let error = reply.paramDescriptor(forKeyword: AEKeyword(keyErrorNumber)) {
      let status: Int32
      switch error.descriptorType {
      case DescType(typeSInt16):
        guard error.data.count == MemoryLayout<Int16>.size else {
          return .failure(.malformedReply)
        }
        status = error.int32Value
      case DescType(typeSInt32):
        guard error.data.count == MemoryLayout<Int32>.size else {
          return .failure(.malformedReply)
        }
        status = error.int32Value
      default:
        return .failure(.malformedReply)
      }
      if status != noErr {
        return .failure(.appleEventError(Self.boundedError(status)))
      }
    }
    return .value(reply)
  }

  private static func boundedError(_ status: Int32) -> PowerPointAppleEventBoundedError {
    switch OSStatus(status) {
    case OSStatus(errAEEventWouldRequireUserConsent):
      .wouldRequireUserConsent
    case OSStatus(errAEEventNotPermitted):
      .notPermitted
    case OSStatus(procNotFound):
      .targetNotRunning
    case OSStatus(errAETimeout):
      .timedOut
    case OSStatus(errAEEventNotHandled):
      .unsupportedOperation
    default:
      .other
    }
  }

  private static func isContainer(_ descriptor: NSAppleEventDescriptor) -> Bool {
    descriptor.descriptorType == DescType(typeNull)
      || descriptor.descriptorType == DescType(typeObjectSpecifier)
  }

  private static func isExactRootActivePresentationAlias(
    _ descriptor: NSAppleEventDescriptor
  ) -> Bool {
    guard
      descriptor.descriptorType == DescType(typeObjectSpecifier),
      descriptor.isRecordDescriptor,
      descriptor.numberOfItems == requiredObjectSpecifierFieldCount,
      let desiredClass = descriptor.forKeyword(AEKeyword(keyAEDesiredClass)),
      desiredClass.descriptorType == DescType(typeType),
      desiredClass.data.count == MemoryLayout<OSType>.size,
      desiredClass.typeCodeValue == PowerPointAppleEventObjectClass.presentation.rawValue,
      let keyForm = descriptor.forKeyword(AEKeyword(keyAEKeyForm)),
      keyForm.descriptorType == DescType(typeEnumerated),
      keyForm.data.count == MemoryLayout<OSType>.size,
      keyForm.enumCodeValue == OSType(formPropertyID),
      let keyData = descriptor.forKeyword(AEKeyword(keyAEKeyData)),
      keyData.descriptorType == DescType(typeType),
      keyData.data.count == MemoryLayout<OSType>.size,
      keyData.typeCodeValue == PowerPointAppleEventProperty.activePresentation.rawValue,
      let container = descriptor.forKeyword(AEKeyword(keyAEContainer)),
      container.descriptorType == DescType(typeNull),
      container.data.isEmpty
    else { return false }
    return true
  }

  private static func isValidRuntimeObjectSpecifier(
    _ descriptor: NSAppleEventDescriptor,
    expectedClass: PowerPointAppleEventObjectClass?,
    depth: Int
  ) -> Bool {
    guard
      depth <= maximumRuntimeObjectSpecifierDepth,
      descriptor.descriptorType == DescType(typeObjectSpecifier),
      descriptor.isRecordDescriptor,
      descriptor.numberOfItems == requiredObjectSpecifierFieldCount,
      descriptor.data.count <= maximumRuntimeObjectSpecifierBytes,
      let desiredClass = descriptor.forKeyword(AEKeyword(keyAEDesiredClass)),
      desiredClass.descriptorType == DescType(typeType),
      desiredClass.data.count == MemoryLayout<OSType>.size,
      let objectClass = PowerPointAppleEventObjectClass(rawValue: desiredClass.typeCodeValue),
      expectedClass == nil || objectClass == expectedClass,
      let keyForm = descriptor.forKeyword(AEKeyword(keyAEKeyForm)),
      keyForm.descriptorType == DescType(typeEnumerated),
      keyForm.data.count == MemoryLayout<OSType>.size,
      let keyData = descriptor.forKeyword(AEKeyword(keyAEKeyData)),
      let container = descriptor.forKeyword(AEKeyword(keyAEContainer)),
      isValidRuntimeKey(for: objectClass, form: keyForm.enumCodeValue, data: keyData),
      isValidRuntimeContainer(container, depth: depth + 1)
    else { return false }
    return true
  }

  private static func isValidRuntimeContainer(
    _ descriptor: NSAppleEventDescriptor,
    depth: Int
  ) -> Bool {
    switch descriptor.descriptorType {
    case DescType(typeNull):
      return descriptor.data.isEmpty
    case DescType(typeObjectSpecifier):
      return isValidRuntimeObjectSpecifier(descriptor, expectedClass: nil, depth: depth)
    default:
      return false
    }
  }

  private static func isValidRuntimeKey(
    for objectClass: PowerPointAppleEventObjectClass,
    form: OSType,
    data: NSAppleEventDescriptor
  ) -> Bool {
    switch form {
    case OSType(formAbsolutePosition):
      return isPositiveInt32Descriptor(data)
    case OSType(formUniqueID):
      return supportsUniqueID(objectClass) && isPositiveInt32Descriptor(data)
    case OSType(formPropertyID):
      return isExpectedPropertyDescriptor(data, for: objectClass)
    case OSType(formName):
      guard supportsName(objectClass) else { return false }
      guard
        data.descriptorType == DescType(typeUnicodeText),
        data.data.count <= maximumRuntimeObjectSpecifierBytes,
        let name = data.stringValue
      else { return false }
      return (1...maximumRuntimeNameUTF16Length).contains(name.utf16.count)
        && !name.contains("\0")
    default:
      return false
    }
  }

  private static func isPositiveInt32Descriptor(_ descriptor: NSAppleEventDescriptor) -> Bool {
    descriptor.descriptorType == DescType(typeSInt32)
      && descriptor.data.count == MemoryLayout<Int32>.size
      && descriptor.int32Value > 0
  }

  private static func isExpectedPropertyDescriptor(
    _ descriptor: NSAppleEventDescriptor,
    for objectClass: PowerPointAppleEventObjectClass
  ) -> Bool {
    guard
      descriptor.descriptorType == DescType(typeType),
      descriptor.data.count == MemoryLayout<OSType>.size,
      let property = PowerPointAppleEventProperty(rawValue: descriptor.typeCodeValue)
    else { return false }
    switch objectClass {
    case .presentation:
      return property == .activePresentation || property == .presentation
    case .slideShowSettings:
      return property == .slideShowSettings
    case .slideShowWindow:
      return property == .slideShowWindow
    case .slideShowView:
      return property == .slideShowView
    case .slide:
      return property == .slide
    }
  }

  private static func supportsUniqueID(_ objectClass: PowerPointAppleEventObjectClass) -> Bool {
    objectClass == .presentation || objectClass == .slide
  }

  private static func supportsName(_ objectClass: PowerPointAppleEventObjectClass) -> Bool {
    objectClass == .presentation || objectClass == .slide
  }
}
