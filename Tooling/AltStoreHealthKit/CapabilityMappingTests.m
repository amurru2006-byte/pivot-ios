// Tests for the unofficial, experimental HealthKit capability mapping.
// No Apple account, device, certificate or health records are used here.
#import <Foundation/Foundation.h>
#import "ALTCapabilities.h"

static NSUInteger assertions = 0;
static void check(BOOL condition, NSString *message) {
    assertions += 1;
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message.UTF8String);
        exit(1);
    }
}

int main(void) {
    @autoreleasepool {
        check([ALTEntitlementHealthKit isEqualToString:@"com.apple.developer.healthkit"], @"Base entitlement spelling");
        check([ALTFeatureHealthKit isEqualToString:@"HK421J6T7P"], @"Apple feature identifier");
        NSArray<ALTEntitlement> *entitlements = @[ALTEntitlementAppGroups, ALTEntitlementInterAppAudio, ALTEntitlementIncreasedMemoryLimit, ALTEntitlementHealthKit];
        NSArray<ALTFeature> *features = @[ALTFeatureAppGroups, ALTFeatureInterAppAudio, ALTFeatureIncreasedMemoryLimit, ALTFeatureHealthKit];
        for (NSUInteger index = 0; index < entitlements.count; index++) {
            check([ALTFeatureForEntitlement(entitlements[index]) isEqualToString:features[index]], @"Forward mapping, including existing features");
            check([ALTEntitlementForFeature(features[index]) isEqualToString:entitlements[index]], @"Reverse mapping, including existing features");
        }
        check(ALTFeatureIsLegacy(ALTFeatureHealthKit), @"HealthKit uses existing legacy App ID registration");
        check(ALTFeatureIsLegacy(ALTFeatureAppGroups), @"App group registration unchanged");
        check(!ALTFeatureIsLegacy(ALTFeatureIncreasedMemoryLimit), @"Memory-limit registration unchanged");
        check(ALTFeatureForEntitlement(@"com.apple.developer.healthkit.access") == nil, @"Do not map array-valued clinical access to a Boolean feature");
        check(ALTFeatureForEntitlement(@"com.apple.developer.healthkit.background-delivery") == nil, @"Background delivery is not an independent App ID feature");
        check(ALTFeatureForEntitlement(@"unknown.entitlement") == nil, @"Unknown entitlements remain unmapped");
        check(ALTEntitlementForFeature(@"unknown.feature") == nil, @"Unknown features remain unmapped");
        fprintf(stdout, "%lu capability assertions passed. Device provisioning is NOT verified.\n", (unsigned long)assertions);
    }
    return 0;
}
