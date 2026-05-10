/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree.
 */


#import "XCUIElement+FBFind.h"

#import "FBMacros.h"
#import "FBElementTypeTransformer.h"
#import "FBConfiguration.h"
#import "NSPredicate+FBFormat.h"
#import "FBXCElementSnapshotWrapper+Helpers.h"
#import "FBXCodeCompatibility.h"
#import "XCUIElement+FBCaching.h"
#import "XCUIElement+FBUID.h"
#import "XCUIElement+FBUtilities.h"
#import "XCUIElement+FBWebDriverAttributes.h"
#import "XCUIElementQuery.h"
#import "FBElementUtils.h"
#import "FBXCodeCompatibility.h"
#import "FBXPath.h"
#import "FBLogger.h"

@implementation XCUIElement (FBFind)

+ (NSArray<XCUIElement *> *)fb_extractMatchingElementsFromQuery:(XCUIElementQuery *)query
                                    shouldReturnAfterFirstMatch:(BOOL)shouldReturnAfterFirstMatch
{
  if (!shouldReturnAfterFirstMatch) {
    return query.fb_allMatches;
  }
  XCUIElement *matchedElement = query.fb_firstMatch;
  return matchedElement ? @[matchedElement] : @[];
}

- (id<FBXCElementSnapshot>)fb_cachedSnapshotWithQuery:(XCUIElementQuery *)query
{
  return [self isKindOfClass:XCUIApplication.class] ? query.rootElementSnapshot : self.fb_cachedSnapshot;
}

#pragma mark - Search by ClassName

- (NSArray<XCUIElement *> *)fb_descendantsMatchingClassName:(NSString *)className
                                shouldReturnAfterFirstMatch:(BOOL)shouldReturnAfterFirstMatch
{
  XCUIElementType type = [FBElementTypeTransformer elementTypeWithTypeName:className];
  XCUIElementQuery *query = [self.fb_query descendantsMatchingType:type];
  NSMutableArray *result = [NSMutableArray array];
  [result addObjectsFromArray:[self.class fb_extractMatchingElementsFromQuery:query
                                                  shouldReturnAfterFirstMatch:shouldReturnAfterFirstMatch]];
  id<FBXCElementSnapshot> cachedSnapshot = [self fb_cachedSnapshotWithQuery:query];
  if (type == XCUIElementTypeAny || cachedSnapshot.elementType == type) {
    if (shouldReturnAfterFirstMatch || result.count == 0) {
      return @[self];
    }
    [result insertObject:self atIndex:0];
  }
  // why: an XCUIApplication query only walks the keyWindow hierarchy. When the app
  // mounts a sibling window (SwiftUI .sheet, etc.), descendants in that window are
  // invisible to the app-rooted query. Retry per-window only when the initial query
  // returned empty so the common single-window path stays single-snapshot.
  if (result.count == 0 && [self isKindOfClass:XCUIApplication.class]) {
    NSArray<XCUIElement *> *windows = [(XCUIApplication *)self windows].allElementsBoundByAccessibilityElement;
    if (windows.count > 1) {
      // Dedupe by object identity: the same underlying AX element can surface under
      // multiple windows during transitions (window swap mid-iteration). Without this
      // the same element appears twice in the result.
      NSMutableSet<NSValue *> *seen = [NSMutableSet set];
      for (XCUIElement *window in windows) {
        @autoreleasepool {
          @try {
            XCUIElementQuery *windowQuery = [window.fb_query descendantsMatchingType:type];
            NSArray<XCUIElement *> *windowMatches =
                [self.class fb_extractMatchingElementsFromQuery:windowQuery
                                    shouldReturnAfterFirstMatch:shouldReturnAfterFirstMatch];
            for (XCUIElement *match in windowMatches) {
              NSValue *key = [NSValue valueWithPointer:(__bridge const void *)match];
              if ([seen containsObject:key]) {
                continue;
              }
              [seen addObject:key];
              [result addObject:match];
            }
            if (shouldReturnAfterFirstMatch && result.count > 0) {
              return result.copy;
            }
          } @catch (NSException *e) {
            [FBLogger logFmt:@"per-window find skipped: %@", e.reason];
            continue;
          }
        }
      }
    }
  }
  return result.copy;
}


#pragma mark - Search by property value

- (NSArray<XCUIElement *> *)fb_descendantsMatchingProperty:(NSString *)property
                                                     value:(NSString *)value
                                             partialSearch:(BOOL)partialSearch
{
  NSPredicate *searchPredicate = [NSPredicate predicateWithFormat:(partialSearch ? @"%K CONTAINS %@" : @"%K == %@"), property, value];
  return [self fb_descendantsMatchingPredicate:searchPredicate shouldReturnAfterFirstMatch:NO];
}

#pragma mark - Search by Predicate String

- (NSArray<XCUIElement *> *)fb_descendantsMatchingPredicate:(NSPredicate *)predicate
                                shouldReturnAfterFirstMatch:(BOOL)shouldReturnAfterFirstMatch
{
  NSPredicate *formattedPredicate = [NSPredicate fb_snapshotBlockPredicateWithPredicate:predicate];
  XCUIElementQuery *query = [[self.fb_query descendantsMatchingType:XCUIElementTypeAny] matchingPredicate:formattedPredicate];
  NSMutableArray<XCUIElement *> *result = [NSMutableArray array];
  [result addObjectsFromArray:[self.class fb_extractMatchingElementsFromQuery:query
                                                  shouldReturnAfterFirstMatch:shouldReturnAfterFirstMatch]];
  id<FBXCElementSnapshot> cachedSnapshot = [self fb_cachedSnapshotWithQuery:query];
  // Include self element into predicate search
  if ([formattedPredicate evaluateWithObject:cachedSnapshot]) {
    if (shouldReturnAfterFirstMatch || result.count == 0) {
      return @[self];
    }
    [result insertObject:self atIndex:0];
  }
  // why: an XCUIApplication query only walks the keyWindow hierarchy, so identifiers
  // that live inside a sibling window (SwiftUI .sheet, etc.) yield zero matches. Retry
  // per-window only when the initial query returned empty so the common single-window
  // path stays single-snapshot. Covers fb_descendantsMatchingIdentifier: and
  // fb_descendantsMatchingProperty: too — both delegate here.
  if (result.count == 0 && [self isKindOfClass:XCUIApplication.class]) {
    NSArray<XCUIElement *> *windows = [(XCUIApplication *)self windows].allElementsBoundByAccessibilityElement;
    if (windows.count > 1) {
      // Dedupe by object identity (see fb_descendantsMatchingClassName: for rationale).
      NSMutableSet<NSValue *> *seen = [NSMutableSet set];
      for (XCUIElement *window in windows) {
        @autoreleasepool {
          @try {
            XCUIElementQuery *windowQuery =
                [[window.fb_query descendantsMatchingType:XCUIElementTypeAny] matchingPredicate:formattedPredicate];
            NSArray<XCUIElement *> *windowMatches =
                [self.class fb_extractMatchingElementsFromQuery:windowQuery
                                    shouldReturnAfterFirstMatch:shouldReturnAfterFirstMatch];
            for (XCUIElement *match in windowMatches) {
              NSValue *key = [NSValue valueWithPointer:(__bridge const void *)match];
              if ([seen containsObject:key]) {
                continue;
              }
              [seen addObject:key];
              [result addObject:match];
            }
            if (shouldReturnAfterFirstMatch && result.count > 0) {
              return result.copy;
            }
          } @catch (NSException *e) {
            [FBLogger logFmt:@"per-window find skipped: %@", e.reason];
            continue;
          }
        }
      }
    }
  }
  return result.copy;
}


#pragma mark - Search by xpath

- (NSArray<XCUIElement *> *)fb_descendantsMatchingXPathQuery:(NSString *)xpathQuery
                                 shouldReturnAfterFirstMatch:(BOOL)shouldReturnAfterFirstMatch
{
  // XPath will try to match elements only class name, so requesting elements by XCUIElementTypeAny will not work. We should use '*' instead.
  xpathQuery = [xpathQuery stringByReplacingOccurrencesOfString:@"XCUIElementTypeAny" withString:@"*"];
  NSArray<id<FBXCElementSnapshot>> *matchingSnapshots = [FBXPath matchesWithRootElement:self forQuery:xpathQuery];
  if (0 == [matchingSnapshots count]) {
    return @[];
  }
  if (shouldReturnAfterFirstMatch) {
    id<FBXCElementSnapshot> snapshot = matchingSnapshots.firstObject;
    matchingSnapshots = @[snapshot];
  }
  XCUIElement *scopeRoot = FBConfiguration.limitXpathContextScope ? self : self.application;
  return [scopeRoot fb_filterDescendantsWithSnapshots:matchingSnapshots
                                         onlyChildren:NO];
}


#pragma mark - Search by Accessibility Id

- (NSArray<XCUIElement *> *)fb_descendantsMatchingIdentifier:(NSString *)accessibilityId
                                 shouldReturnAfterFirstMatch:(BOOL)shouldReturnAfterFirstMatch
{
  NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(id<FBXCElementSnapshot> snapshot,
                                                                 NSDictionary<NSString *,id> * _Nullable bindings) {
    @autoreleasepool {
      return [[FBXCElementSnapshotWrapper wdNameWithSnapshot:snapshot] isEqualToString:accessibilityId];
    }
  }];
  return [self fb_descendantsMatchingPredicate:predicate
                   shouldReturnAfterFirstMatch:shouldReturnAfterFirstMatch];
}

@end
