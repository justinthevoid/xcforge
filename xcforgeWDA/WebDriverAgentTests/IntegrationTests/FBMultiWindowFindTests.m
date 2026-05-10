/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import "FBIntegrationTestCase.h"
#import "FBMacros.h"
#import "FBTestMacros.h"
#import "XCUIApplication.h"
#import "XCUIApplication+FBHelpers.h"
#import "XCUIElement+FBFind.h"

// Identifier exposed by a host fixture that pushes a sibling UIWindow on demand.
// IntegrationApp does not currently ship one; tests are skipped unless the host
// app exposes both these identifiers.
static NSString *const FBOpenSecondaryWindowButtonId = @"open.secondary.window";
static NSString *const FBSecondaryWindowSheetId = @"home.drawer";
static NSString *const FBSecondaryWindowDoneId = @"home.drawer.done";

@interface FBMultiWindowFindTests : FBIntegrationTestCase
@end

@implementation FBMultiWindowFindTests

- (void)setUp
{
  [super setUp];
  [self launchApplication];
}

// Open the secondary window the host fixture should expose. Returns NO when no such
// button exists; callers should XCTSkipUnless on the result.
- (BOOL)openSecondaryWindowIfPossible
{
  XCUIElement *trigger = self.testedApplication.buttons[FBOpenSecondaryWindowButtonId];
  if (!trigger.exists) {
    return NO;
  }
  [trigger tap];
  XCUIElement *sheet = self.testedApplication.otherElements[FBSecondaryWindowSheetId];
  return [sheet waitForExistenceWithTimeout:2.0];
}

- (void)testSourceIncludesSecondaryWindow
{
  XCTSkipUnless([self openSecondaryWindowIfPossible],
                @"Host fixture does not expose a secondary-window trigger; skipping multi-window source test.");

  NSDictionary *tree = self.testedApplication.fb_tree;
  NSString *xml = [self.testedApplication fb_xmlRepresentation];

  XCTAssertNotNil(tree);
  XCTAssertNotNil(xml);
  XCTAssertTrue([xml containsString:FBSecondaryWindowSheetId],
                @"Multi-window XML source must include the secondary window's sheet identifier");
}

- (void)testFindByIdReachesSheetElement
{
  XCTSkipUnless([self openSecondaryWindowIfPossible],
                @"Host fixture does not expose a secondary-window trigger; skipping multi-window find test.");

  NSArray<XCUIElement *> *matches =
      [self.testedApplication fb_descendantsMatchingIdentifier:FBSecondaryWindowDoneId
                                  shouldReturnAfterFirstMatch:YES];
  XCTAssertGreaterThan(matches.count, 0u,
                       @"App-rooted find must reach a sheet-window element via the per-window retry path");
}

- (void)testCoordinateTapDispatchesToSheet
{
  XCTSkipUnless([self openSecondaryWindowIfPossible],
                @"Host fixture does not expose a secondary-window trigger; skipping multi-window tap test.");

  XCUIElement *done = self.testedApplication.buttons[FBSecondaryWindowDoneId];
  XCTAssertTrue([done waitForExistenceWithTimeout:2.0]);
  CGRect frame = done.frame;
  CGPoint center = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));

  XCUICoordinate *origin = [self.testedApplication coordinateWithNormalizedOffset:CGVectorMake(0, 0)];
  XCUICoordinate *target = [origin coordinateWithOffset:CGVectorMake(center.x, center.y)];
  [target tap];

  XCUIElement *sheet = self.testedApplication.otherElements[FBSecondaryWindowSheetId];
  FBAssertWaitTillBecomesTrue(!sheet.exists);
}

@end
