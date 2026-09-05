import ApplicationServices
import Foundation
import Testing

@testable import LectureBoard_AI

/// Pure descriptor tests only. They never call `sendEvent`, the permission API, or PowerPoint.
struct PowerPointAppleEventDescriptorCodecTests {
  @Test func fixedCodesAndNoninteractiveSendPolicyMatchPrimarySpecifications() {
    #expect(PowerPointAppleEventCode.activePresentation == fourCC("AAPr"))
    #expect(PowerPointAppleEventCode.presentation == fourCC("pptP"))
    #expect(PowerPointAppleEventCode.slideShowSettings == fourCC("SSSt"))
    #expect(PowerPointAppleEventCode.slideShowWindow == fourCC("pSSw"))
    #expect(PowerPointAppleEventCode.slideShowView == fourCC("PSSv"))
    #expect(PowerPointAppleEventCode.slide == fourCC("pSLD"))
    #expect(PowerPointAppleEventCode.slideState == fourCC("SsTe"))
    #expect(PowerPointAppleEventCode.slideID == fourCC("SlID"))
    #expect(PowerPointAppleEventCode.slideIndex == fourCC("SIdX"))
    #expect(PowerPointAppleEventCode.presentationSaved == fourCC("save"))
    #expect(PowerPointAppleEventCode.visible == fourCC("pvis"))
    #expect(PowerPointAppleEventCode.slideShowType == fourCC("SwTy"))
    #expect(PowerPointAppleEventCode.powerPointSuite == fourCC("sPPT"))
    #expect(PowerPointAppleEventCode.runSlideShow == fourCC("RSsH"))
    #expect(PowerPointAppleEventCode.exitSlideShow == fourCC("xSsw"))
    #expect(PowerPointAppleEventCode.running == 0x00D3_0001)
    #expect(PowerPointAppleEventCode.black == 0x00D3_0003)
    #expect(PowerPointAppleEventCode.white == 0x00D3_0004)

    #expect(
      PowerPointAppleEventDescriptorCodec.sendOptions.rawValue
        == UInt(kAEWaitReply | kAENeverInteract | kAEDoNotPromptForUserConsent)
    )
    #expect(PowerPointAppleEventDescriptorCodec.sendOptions.contains(.waitForReply))
    #expect(PowerPointAppleEventDescriptorCodec.sendOptions.contains(.neverInteract))
    #expect(!PowerPointAppleEventDescriptorCodec.sendOptions.contains(.canInteract))
    #expect(!PowerPointAppleEventDescriptorCodec.sendOptions.contains(.alwaysInteract))
  }

  @Test func targetAndObjectSpecifiersRetainExactTypedStructure() throws {
    let codec = PowerPointAppleEventDescriptorCodec()
    let target = try #require(codec.targetDescriptor(processIdentifier: 700))
    #expect(target.descriptorType == DescType(typeKernelProcessID))
    #expect(decodedInt32(target) == 700)
    #expect(codec.targetDescriptor(processIdentifier: 0) == nil)

    let activePresentation = try #require(
      codec.rootPropertySpecifier(.activePresentation)
    )
    expectObjectSpecifier(
      activePresentation,
      desiredClass: OSType(typeProperty),
      keyForm: OSType(formPropertyID),
      keyType: DescType(typeType),
      keyCode: PowerPointAppleEventCode.activePresentation,
      containerType: DescType(typeNull)
    )

    let firstWindow = try #require(
      codec.elementSpecifier(.slideShowWindow, at: 1, in: activePresentation)
    )
    expectObjectSpecifier(
      firstWindow,
      desiredClass: PowerPointAppleEventCode.slideShowWindow,
      keyForm: OSType(formAbsolutePosition),
      keyType: DescType(typeSInt32),
      keyInt32: 1,
      containerType: DescType(typeObjectSpecifier)
    )
    #expect(codec.elementSpecifier(.slideShowWindow, at: 0, in: activePresentation) == nil)

    let nested = try #require(
      codec.nestedPropertySpecifier([
        .activePresentation,
        .slideShowWindow,
        .slideShowView,
        .slide,
        .slideID,
      ])
    )
    expectObjectSpecifier(
      nested,
      desiredClass: OSType(typeProperty),
      keyForm: OSType(formPropertyID),
      keyType: DescType(typeType),
      keyCode: PowerPointAppleEventCode.slideID,
      containerType: DescType(typeObjectSpecifier)
    )
    #expect(codec.nestedPropertySpecifier([]) == nil)
    #expect(codec.nestedPropertySpecifier(Array(repeating: .slide, count: 9)) == nil)
  }

  @Test func coreAndRunEventsHaveExactTargetDirectParametersAndData() throws {
    let codec = PowerPointAppleEventDescriptorCodec()
    let settings = try #require(
      codec.nestedPropertySpecifier([.activePresentation, .slideShowSettings])
    )

    let get = try #require(codec.getEvent(processIdentifier: 700, object: settings))
    expectEvent(
      get,
      eventClass: OSType(kAECoreSuite),
      eventID: OSType(kAEGetData),
      processIdentifier: 700,
      directObject: settings
    )

    let count = try #require(
      codec.countEvent(
        processIdentifier: 701,
        objectClass: .slideShowWindow,
        in: nullDescriptor()
      )
    )
    expectEvent(
      count,
      eventClass: OSType(kAECoreSuite),
      eventID: OSType(kAECountElements),
      processIdentifier: 701,
      directObjectType: DescType(typeNull)
    )
    let countClass = try #require(
      count.paramDescriptor(forKeyword: AEKeyword(keyAEObjectClass))
    )
    #expect(countClass.descriptorType == DescType(typeType))
    #expect(countClass.typeCodeValue == PowerPointAppleEventCode.slideShowWindow)

    let visible = try #require(codec.rootPropertySpecifier(.visible))
    let setVisible = try #require(
      codec.setBooleanEvent(processIdentifier: 702, object: visible, value: false)
    )
    expectEvent(
      setVisible,
      eventClass: OSType(kAECoreSuite),
      eventID: OSType(kAESetData),
      processIdentifier: 702,
      directObject: visible
    )
    let booleanData = try #require(
      setVisible.paramDescriptor(forKeyword: AEKeyword(keyAEData))
    )
    #expect(booleanData.descriptorType == DescType(typeBoolean))
    #expect(booleanData.booleanValue == false)

    let state = try #require(codec.rootPropertySpecifier(.slideState))
    let setState = try #require(
      codec.setSlideShowStateEvent(processIdentifier: 703, object: state, value: .white)
    )
    let enumData = try #require(setState.paramDescriptor(forKeyword: AEKeyword(keyAEData)))
    #expect(enumData.descriptorType == DescType(typeEnumerated))
    #expect(enumData.enumCodeValue == PowerPointAppleEventCode.white)

    let run = try #require(codec.runSlideShowEvent(processIdentifier: 704, settings: settings))
    expectEvent(
      run,
      eventClass: PowerPointAppleEventCode.powerPointSuite,
      eventID: PowerPointAppleEventCode.runSlideShow,
      processIdentifier: 704,
      directObject: settings
    )
    #expect(codec.getEvent(processIdentifier: -1, object: settings) == nil)
    #expect(
      codec.runSlideShowEvent(
        processIdentifier: 704,
        settings: NSAppleEventDescriptor(string: "not an object")
      ) == nil
    )
  }

  @Test func typedReplyParsersAcceptOnlyExactDescriptorTypes() throws {
    let codec = PowerPointAppleEventDescriptorCodec()

    switch codec.parseInt32Reply(reply(direct: NSAppleEventDescriptor(int32: 42))) {
    case .value(let value):
      #expect(value == 42)
    case .failure(let failure):
      Issue.record("Unexpected Int32 parse failure: \(failure)")
    }
    switch codec.parseBooleanReply(reply(direct: NSAppleEventDescriptor(boolean: true))) {
    case .value(let value):
      #expect(value)
    case .failure(let failure):
      Issue.record("Unexpected Boolean parse failure: \(failure)")
    }
    for state in PowerPointSlideShowState.allCases {
      switch codec.parseSlideShowStateReply(
        reply(direct: NSAppleEventDescriptor(enumCode: state.rawValue))
      ) {
      case .value(let parsed):
        #expect(parsed == state)
      case .failure(let failure):
        Issue.record("Unexpected enum parse failure: \(failure)")
      }
    }
    for showType in PowerPointSlideShowType.allCases {
      switch codec.parseSlideShowTypeReply(
        reply(direct: NSAppleEventDescriptor(enumCode: showType.rawValue))
      ) {
      case .value(let parsed): #expect(parsed == showType)
      case .failure(let failure): Issue.record("Unexpected show-type parse failure: \(failure)")
      }
    }
    if case .failure(.unsupportedSlideShowType) = codec.parseSlideShowTypeReply(
      reply(direct: NSAppleEventDescriptor(enumCode: 0x00D5_00FF))
    ) {
    } else {
      Issue.record("Unknown show type must fail closed")
    }

    let object = try #require(
      codec.elementSpecifier(
        .slideShowWindow,
        at: 1,
        in: nullDescriptor()
      )
    )
    switch codec.parseObjectSpecifierReply(
      reply(direct: object),
      expectedClass: .slideShowWindow
    ) {
    case .value(let runtime):
      object.setDescriptor(
        NSAppleEventDescriptor(int32: 99),
        forKeyword: AEKeyword(keyAEKeyData)
      )
      let nested = try #require(codec.propertySpecifier(.slideShowView, of: runtime))
      let container = try #require(
        nested.forKeyword(AEKeyword(keyAEContainer))
      )
      #expect(container.descriptorType == DescType(typeObjectSpecifier))
      #expect(
        container.forKeyword(AEKeyword(keyAEKeyData))?.int32Value == 1,
        "The runtime wrapper must retain an immutable copy of the accepted descriptor"
      )
    case .failure(let failure):
      Issue.record("Unexpected object parse failure: \(failure)")
    }
  }

  @Test func exactReturnedObjectBuildsRoleSemanticRestorationAndExitPaths() throws {
    let codec = PowerPointAppleEventDescriptorCodec()
    let returned = try #require(
      codec.elementSpecifier(.slideShowWindow, at: 7, in: nullDescriptor())
    )
    let runtime: PowerPointAppleEventRuntimeObjectSpecifier
    switch codec.parseObjectSpecifierReply(
      reply(direct: returned),
      expectedClass: .slideShowWindow
    ) {
    case .value(let object):
      runtime = object
    case .failure(let failure):
      Issue.record("Unexpected returned-object parse failure: \(failure)")
      return
    }

    for (properties, leaf) in [
      ([PowerPointAppleEventProperty.visible], PowerPointAppleEventProperty.visible),
      ([.slideShowView, .slideState], .slideState),
      ([.slideShowView, .slide, .slideID], .slideID),
      ([.slideShowView, .slide, .slideIndex], .slideIndex),
      ([.presentation, .presentationSaved], .presentationSaved),
    ] {
      let property = try #require(
        codec.nestedPropertySpecifier(properties, of: runtime)
      )
      #expect(propertyLeafCode(property) == leaf.rawValue)
      #expect(rootObjectIndex(property) == 7)
      #expect(rootObjectClass(property) == .slideShowWindow)
    }
    #expect(codec.nestedPropertySpecifier([], of: runtime) == nil)

    let exit = try #require(
      codec.exitSlideShowEvent(processIdentifier: 700, slideShowWindow: runtime)
    )
    expectEvent(
      exit,
      eventClass: PowerPointAppleEventCode.powerPointSuite,
      eventID: PowerPointAppleEventCode.exitSlideShow,
      processIdentifier: 700,
      directObjectType: DescType(typeObjectSpecifier)
    )
    let exitView = try #require(
      exit.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))
    )
    #expect(propertyLeafCode(exitView) == PowerPointAppleEventCode.slideShowView)
    #expect(rootObjectIndex(exitView) == 7)

    switch codec.parseCommandReply(reply(direct: nil)) {
    case .value:
      break
    case .failure(let failure):
      Issue.record("Unexpected empty command reply failure: \(failure)")
    }
    switch codec.parseCommandReply(
      reply(direct: NSAppleEventDescriptor.null())
    ) {
    case .value:
      break
    case .failure(let failure):
      Issue.record("Unexpected null command reply failure: \(failure)")
    }
    expectFailure(
      codec.parseCommandReply(reply(direct: NSAppleEventDescriptor(boolean: true))),
      .unexpectedDirectParameterType
    )
  }

  @Test func objectSpecifierRepliesAllowOnlyClassSpecificFormsAndBoundedContainers() throws {
    let codec = PowerPointAppleEventDescriptorCodec()
    let null = nullDescriptor()

    let activePresentation = try #require(
      objectSpecifier(
        desiredClass: .presentation,
        keyForm: OSType(formPropertyID),
        keyData: NSAppleEventDescriptor(typeCode: PowerPointAppleEventCode.activePresentation),
        container: null
      )
    )
    switch codec.parseObjectSpecifierReply(
      reply(direct: activePresentation), expectedClass: .presentation)
    {
    case .value:
      break
    case .failure(let failure):
      Issue.record("Unexpected property-form parse failure: \(failure)")
    }

    let propertyMismatch = try #require(
      objectSpecifier(
        desiredClass: .slideShowWindow,
        keyForm: OSType(formPropertyID),
        keyData: NSAppleEventDescriptor(typeCode: PowerPointAppleEventCode.slideShowView),
        container: null
      )
    )
    expectFailure(
      codec.parseObjectSpecifierReply(
        reply(direct: propertyMismatch), expectedClass: .slideShowWindow),
      .malformedObjectSpecifier
    )

    let presentation = try #require(
      objectSpecifier(
        desiredClass: .presentation,
        keyForm: OSType(formAbsolutePosition),
        keyData: NSAppleEventDescriptor(int32: 1),
        container: null
      )
    )
    let settings = try #require(
      objectSpecifier(
        desiredClass: .slideShowSettings,
        keyForm: OSType(formPropertyID),
        keyData: NSAppleEventDescriptor(typeCode: PowerPointAppleEventCode.slideShowSettings),
        container: presentation
      )
    )
    let window = try #require(
      objectSpecifier(
        desiredClass: .slideShowWindow,
        keyForm: OSType(formAbsolutePosition),
        keyData: NSAppleEventDescriptor(int32: 1),
        container: settings
      )
    )
    let view = try #require(
      objectSpecifier(
        desiredClass: .slideShowView,
        keyForm: OSType(formAbsolutePosition),
        keyData: NSAppleEventDescriptor(int32: 1),
        container: window
      )
    )
    switch codec.parseObjectSpecifierReply(reply(direct: view), expectedClass: .slideShowView) {
    case .value:
      break
    case .failure(let failure):
      Issue.record("Unexpected bounded nested parse failure: \(failure)")
    }

    let tooDeep = try #require(
      objectSpecifier(
        desiredClass: .slide,
        keyForm: OSType(formAbsolutePosition),
        keyData: NSAppleEventDescriptor(int32: 1),
        container: view
      )
    )
    expectFailure(
      codec.parseObjectSpecifierReply(reply(direct: tooDeep), expectedClass: .slide),
      .malformedObjectSpecifier
    )

    let oversizedContainer = try #require(
      objectSpecifier(
        desiredClass: .presentation,
        keyForm: OSType(formName),
        keyData: NSAppleEventDescriptor(string: String(repeating: "x", count: 1_025)),
        container: null
      )
    )
    let oversizedNested = try #require(
      objectSpecifier(
        desiredClass: .slideShowWindow,
        keyForm: OSType(formAbsolutePosition),
        keyData: NSAppleEventDescriptor(int32: 1),
        container: oversizedContainer
      )
    )
    expectFailure(
      codec.parseObjectSpecifierReply(
        reply(direct: oversizedNested), expectedClass: .slideShowWindow),
      .malformedObjectSpecifier
    )

    let malformedContainer = try #require(
      malformedObjectSpecifier(
        desiredClass: PowerPointAppleEventCode.slideShowView,
        keyForm: OSType(formRange),
        keyData: NSAppleEventDescriptor(int32: 1),
        container: null
      )
    )
    let malformedNested = try #require(
      objectSpecifier(
        desiredClass: .slideShowWindow,
        keyForm: OSType(formAbsolutePosition),
        keyData: NSAppleEventDescriptor(int32: 1),
        container: malformedContainer
      )
    )
    expectFailure(
      codec.parseObjectSpecifierReply(
        reply(direct: malformedNested), expectedClass: .slideShowWindow),
      .malformedObjectSpecifier
    )

    let extraField = try #require(
      objectSpecifier(
        desiredClass: .slideShowWindow,
        keyForm: OSType(formAbsolutePosition),
        keyData: NSAppleEventDescriptor(int32: 1),
        container: null,
        extraField: true
      )
    )
    expectFailure(
      codec.parseObjectSpecifierReply(reply(direct: extraField), expectedClass: .slideShowWindow),
      .malformedObjectSpecifier
    )
  }

  @Test func malformedAndErrorRepliesFailClosedWithoutRawPayloads() throws {
    let codec = PowerPointAppleEventDescriptorCodec()
    let nullContainer = nullDescriptor()

    expectFailure(codec.parseInt32Reply(nil), .missingReply)
    expectFailure(
      codec.parseInt32Reply(
        reply(
          direct: NSAppleEventDescriptor(int32: 42),
          eventClass: AEEventClass(kAECoreSuite) + 1
        )
      ),
      .malformedReply
    )
    expectFailure(
      codec.parseInt32Reply(
        reply(
          direct: NSAppleEventDescriptor(int32: 42),
          eventID: AEEventID(kAEAnswer) + 1
        )
      ),
      .malformedReply
    )
    let nonEventReply = NSAppleEventDescriptor.record()
    nonEventReply.setDescriptor(
      NSAppleEventDescriptor(int32: 42),
      forKeyword: AEKeyword(keyDirectObject)
    )
    expectFailure(codec.parseInt32Reply(nonEventReply), .malformedReply)
    expectFailure(codec.parseInt32Reply(reply(direct: nil)), .missingDirectParameter)
    expectFailure(
      codec.parseInt32Reply(reply(direct: NSAppleEventDescriptor(string: "42"))),
      .unexpectedDirectParameterType
    )
    expectFailure(
      codec.parseInt32Reply(
        reply(
          direct: NSAppleEventDescriptor(int32: 42),
          error: NSAppleEventDescriptor(string: "not an error number")
        )
      ),
      .malformedReply
    )
    expectFailure(
      codec.parseSlideShowStateReply(
        reply(direct: NSAppleEventDescriptor(enumCode: 0x00D3_0002))
      ),
      .unsupportedSlideShowState
    )

    let malformedObject = NSAppleEventDescriptor.record().coerce(
      toDescriptorType: DescType(typeObjectSpecifier)
    )
    expectFailure(
      codec.parseObjectSpecifierReply(
        reply(direct: malformedObject), expectedClass: .slideShowWindow),
      .malformedObjectSpecifier
    )
    let wrongObject = PowerPointAppleEventDescriptorCodec().elementSpecifier(
      .presentation,
      at: 1,
      in: nullContainer
    )
    expectFailure(
      codec.parseObjectSpecifierReply(reply(direct: wrongObject), expectedClass: .slideShowWindow),
      .malformedObjectSpecifier
    )
    for malformedCandidate in [
      malformedObjectSpecifier(
        desiredClass: PowerPointAppleEventCode.slideShowWindow,
        keyForm: OSType(formAbsolutePosition),
        keyData: NSAppleEventDescriptor(int32: 0),
        container: nullContainer
      ),
      malformedObjectSpecifier(
        desiredClass: PowerPointAppleEventCode.slideShowWindow,
        keyForm: OSType(formRange),
        keyData: NSAppleEventDescriptor(int32: 1),
        container: nullContainer
      ),
      malformedObjectSpecifier(
        desiredClass: PowerPointAppleEventCode.slideShowWindow,
        keyForm: OSType(formAbsolutePosition),
        keyData: NSAppleEventDescriptor(int32: 1),
        container: NSAppleEventDescriptor(string: "not a container")
      ),
    ] {
      let malformed = try #require(malformedCandidate)
      expectFailure(
        codec.parseObjectSpecifierReply(
          reply(direct: malformed), expectedClass: .slideShowWindow),
        .malformedObjectSpecifier
      )
    }

    let statuses: [(OSStatus, PowerPointAppleEventBoundedError)] = [
      (OSStatus(errAEEventWouldRequireUserConsent), .wouldRequireUserConsent),
      (OSStatus(errAEEventNotPermitted), .notPermitted),
      (OSStatus(procNotFound), .targetNotRunning),
      (OSStatus(errAETimeout), .timedOut),
      (OSStatus(errAEEventNotHandled), .unsupportedOperation),
      (OSStatus(-12_345), .other),
    ]
    for (status, expected) in statuses {
      expectFailure(
        codec.parseBooleanReply(
          reply(
            direct: NSAppleEventDescriptor(boolean: true),
            error: NSAppleEventDescriptor(int32: status)
          )
        ),
        .appleEventError(expected)
      )
    }
  }
}

private func reply(
  direct: NSAppleEventDescriptor?,
  error: NSAppleEventDescriptor? = nil,
  eventClass: AEEventClass = AEEventClass(kAECoreSuite),
  eventID: AEEventID = AEEventID(kAEAnswer)
) -> NSAppleEventDescriptor {
  let reply = NSAppleEventDescriptor(
    eventClass: eventClass,
    eventID: eventID,
    targetDescriptor: nil,
    returnID: AEReturnID(kAutoGenerateReturnID),
    transactionID: AETransactionID(kAnyTransactionID)
  )
  if let direct {
    reply.setParam(direct, forKeyword: AEKeyword(keyDirectObject))
  }
  if let error {
    reply.setParam(error, forKeyword: AEKeyword(keyErrorNumber))
  }
  return reply
}

private func malformedObjectSpecifier(
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

private func objectSpecifier(
  desiredClass: PowerPointAppleEventObjectClass,
  keyForm: OSType,
  keyData: NSAppleEventDescriptor,
  container: NSAppleEventDescriptor,
  extraField: Bool = false
) -> NSAppleEventDescriptor? {
  let record = NSAppleEventDescriptor.record()
  record.setDescriptor(
    NSAppleEventDescriptor(typeCode: desiredClass.rawValue),
    forKeyword: AEKeyword(keyAEDesiredClass)
  )
  record.setDescriptor(
    NSAppleEventDescriptor(enumCode: keyForm),
    forKeyword: AEKeyword(keyAEKeyForm)
  )
  record.setDescriptor(keyData, forKeyword: AEKeyword(keyAEKeyData))
  record.setDescriptor(container, forKeyword: AEKeyword(keyAEContainer))
  if extraField {
    record.setDescriptor(
      NSAppleEventDescriptor(int32: 1),
      forKeyword: AEKeyword(keyAEData)
    )
  }
  return record.coerce(toDescriptorType: DescType(typeObjectSpecifier))
}

private func nullDescriptor() -> NSAppleEventDescriptor {
  NSAppleEventDescriptor.null()
}

private func expectObjectSpecifier(
  _ descriptor: NSAppleEventDescriptor,
  desiredClass: OSType,
  keyForm: OSType,
  keyType: DescType,
  keyCode: OSType? = nil,
  keyInt32: Int32? = nil,
  containerType: DescType
) {
  #expect(descriptor.descriptorType == DescType(typeObjectSpecifier))
  let desired = descriptor.forKeyword(AEKeyword(keyAEDesiredClass))
  #expect(desired?.descriptorType == DescType(typeType))
  #expect(desired?.typeCodeValue == desiredClass)
  let form = descriptor.forKeyword(AEKeyword(keyAEKeyForm))
  #expect(form?.descriptorType == DescType(typeEnumerated))
  #expect(form?.enumCodeValue == keyForm)
  let key = descriptor.forKeyword(AEKeyword(keyAEKeyData))
  #expect(key?.descriptorType == keyType)
  if let keyCode { #expect(key?.typeCodeValue == keyCode) }
  if let keyInt32 { #expect(key?.int32Value == keyInt32) }
  #expect(
    descriptor.forKeyword(AEKeyword(keyAEContainer))?.descriptorType
      == containerType
  )
}

private func expectEvent(
  _ event: NSAppleEventDescriptor,
  eventClass: OSType,
  eventID: OSType,
  processIdentifier: Int32,
  directObject: NSAppleEventDescriptor? = nil,
  directObjectType: DescType? = nil
) {
  #expect(event.eventClass == AEEventClass(eventClass))
  #expect(event.eventID == AEEventID(eventID))
  let target = event.attributeDescriptor(forKeyword: AEKeyword(keyAddressAttr))
  #expect(target?.descriptorType == DescType(typeKernelProcessID))
  #expect(target.flatMap(decodedInt32) == processIdentifier)
  let direct = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))
  if let directObject {
    #expect(direct?.descriptorType == directObject.descriptorType)
    #expect(direct?.data == directObject.data)
  }
  if let directObjectType { #expect(direct?.descriptorType == directObjectType) }
}

private func decodedInt32(_ descriptor: NSAppleEventDescriptor) -> Int32? {
  guard descriptor.data.count == MemoryLayout<Int32>.size else { return nil }
  return descriptor.data.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
}

private func propertyLeafCode(_ descriptor: NSAppleEventDescriptor) -> OSType? {
  descriptor.forKeyword(AEKeyword(keyAEKeyData))?.typeCodeValue
}

private func rootObjectIndex(_ descriptor: NSAppleEventDescriptor) -> Int32? {
  var current = descriptor
  while current.forKeyword(AEKeyword(keyAEDesiredClass))?.typeCodeValue
    == OSType(typeProperty),
    let container = current.forKeyword(AEKeyword(keyAEContainer))
  {
    current = container
  }
  return current.forKeyword(AEKeyword(keyAEKeyData))?.int32Value
}

private func rootObjectClass(
  _ descriptor: NSAppleEventDescriptor
) -> PowerPointAppleEventObjectClass? {
  var current = descriptor
  while current.forKeyword(AEKeyword(keyAEDesiredClass))?.typeCodeValue
    == OSType(typeProperty),
    let container = current.forKeyword(AEKeyword(keyAEContainer))
  {
    current = container
  }
  guard
    let value = current.forKeyword(AEKeyword(keyAEDesiredClass))?.typeCodeValue
  else { return nil }
  return PowerPointAppleEventObjectClass(rawValue: value)
}

private func fourCC(_ string: String) -> OSType {
  string.utf8.reduce(0) { ($0 << 8) | OSType($1) }
}

private func expectFailure<Value>(
  _ result: PowerPointAppleEventParsed<Value>,
  _ expected: PowerPointAppleEventReplyFailure
) {
  switch result {
  case .value:
    Issue.record("Expected a fail-closed reply parse")
  case .failure(let failure):
    #expect(failure == expected)
  }
}
