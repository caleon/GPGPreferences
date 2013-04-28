//
//  UpdateButton.m
//  GPGTools
//
//  Created by Alexander Willner on 04.08.10.
//  Edited by Roman Zechmeister 11.07.2011
//  Copyright 2010 GPGTools Project Team. All rights reserved.
//

#import "GPGToolsPrefController.h"
#import <Security/Security.h>
#import <Security/SecItem.h>

#define GPG_SERVICE_NAME "GnuPG"

static NSString * const kKeyserver = @"keyserver";
static NSString * const kAutoKeyLocate = @"auto-key-locate";


@implementation GPGToolsPrefController
@synthesize options;

- (id)init {
	if (!(self = [super init])) {
		return nil;
	}
	secretKeysLock = [[NSLock alloc] init];

	gpgc = [GPGController new];
	gpgc.delegate = self;
	
	options = [[GPGOptions sharedOptions] retain];

	return self;
}
- (void)dealloc {
	[gpgc release];
	[secretKeysLock release];
	[options release];
	[super dealloc];
}


- (NSString *)comments {
	return [[options valueInGPGConfForKey:@"comment"] componentsJoinedByString:@"\n"];
}
- (void)setComments:(NSString *)value {
	NSArray *lines = [value componentsSeparatedByString:@"\n"];
	NSMutableArray *filteredLines = [NSMutableArray array];
	NSCharacterSet *whitespaceCharacterSet = [NSCharacterSet whitespaceCharacterSet];
	NSCharacterSet *nonWhitespaceCharacterSet = [whitespaceCharacterSet invertedSet];
	
	[lines enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
		if ([obj rangeOfCharacterFromSet:nonWhitespaceCharacterSet].length > 0) {
			[filteredLines addObject:[obj stringByTrimmingCharactersInSet:whitespaceCharacterSet]];
		}
	}];
	
	
	[options setValueInGPGConf:filteredLines forKey:@"comment"];
}



+ (NSSet *)keyPathsForValuesAffectingValueForKey:(NSString *)key {
	NSSet *mySet = nil;
	NSSet *keysAffectedBySecretKeys = [NSSet setWithObjects:@"secretKeyDescriptions", @"indexOfSelectedSecretKey", nil];
	if ([keysAffectedBySecretKeys containsObject:key]) {
		mySet = [NSSet setWithObject:@"secretKeys"];
	}
	NSSet *superSet = [super keyPathsForValuesAffectingValueForKey:key];
	return [superSet setByAddingObjectsFromSet:mySet];
}


/*
 * Delete stored passphrases from the Mac OS X keychain.
 */
- (IBAction)deletePassphrases:(id)sender {
	@try {
		[options gpgAgentFlush];
		
		NSDictionary *query = [NSDictionary dictionaryWithObjectsAndKeys:@"genp", kSecClass, kSecMatchLimitAll, kSecMatchLimit, kCFBooleanTrue, kSecReturnRef, kCFBooleanTrue, kSecReturnAttributes, @"GnuPG", kSecAttrService, nil];
		
		NSArray *result = nil;
		OSStatus status = SecItemCopyMatching((CFDictionaryRef)query, (CFTypeRef *)&result);
		
		NSCharacterSet *nonHexCharSet = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"] invertedSet];
		
		if (status == noErr) {
			for (NSDictionary *item in result) {
				if (![[item objectForKey:kSecAttrService] isEqualToString:@"GnuPG"]) {
					continue;
				}
				
				NSString *fingerprint = [item objectForKey:kSecAttrAccount];
				if ([fingerprint length] < 8 || [fingerprint length] > 40) {
					continue;
				}
				if ([fingerprint rangeOfCharacterFromSet:nonHexCharSet].length > 0) {
					continue;
				}				

				status = SecKeychainItemDelete((SecKeychainItemRef)[item objectForKey:kSecValueRef]);
				if (status) {
					NSLog(@"ERROR %i: %@", status, SecCopyErrorMessageString(status, nil));
				}
			}
		}
		
		[result release];
		
	} @catch (NSException *exception) {
		NSLog(@"deletePassphrases failed: %@", exception);
	}
}



/*
 * Get and set the PassphraseCacheTime, with a dafault value of 600.
 */
- (NSInteger)passphraseCacheTime {
	NSNumber *value = [options valueForKey:@"PassphraseCacheTime"];
	if (!value) {
		[self setPassphraseCacheTime:600];
		return 600;
	}
	return [value integerValue];
}
- (void)setPassphraseCacheTime:(NSInteger)value {
	[options setValue:[NSNumber numberWithInteger:value] forKey:@"PassphraseCacheTime"];
}



/*
 * Handle external key changes.
 */
- (void)gpgController:(GPGController *)gpgc keysDidChanged:(NSObject<EnumerationList> *)keys external:(BOOL)external {
	[self willChangeValueForKey:@"secretKeys"];
	[secretKeysLock lock];
	[secretKeys release];
	secretKeys = nil;
	[secretKeysLock unlock];
	[self didChangeValueForKey:@"secretKeys"];
}


/*
 * Returns all usable secret keys.
 */
- (NSArray *)secretKeys {
	[secretKeysLock lock];
	if (!secretKeys) {
		secretKeys = [[[[gpgc allSecretKeys] usableGPGKeys] allObjects] retain];
	}
	NSArray *value = [[secretKeys retain] autorelease];
	[secretKeysLock unlock];
	return value;
}



/*
 * The NSBundle for GPGPreferences.prefPane.
 */
- (NSBundle *)myBundle {
	if (!myBundle) {
		myBundle = [NSBundle bundleForClass:[self class]];
	}
	return myBundle;
}

/*
 * Open FAQ.
 *
 */
- (IBAction)openFAQ:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://gpgtools.org/faq.html"]];
}

/*
 * Open Contact.
 *
 */
- (IBAction)openContact:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://gpgtools.org/about.html"]];
}

/*
 * Open Donate.
 *
 */
- (IBAction)openDonate:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://gpgtools.org/donate.html"]];
}


/*
 * Give the credits from Credits.rtf.
 */
- (NSAttributedString *)credits {
	return [[[NSAttributedString alloc] initWithPath:[self.myBundle pathForResource:@"Credits" ofType:@"rtf"] documentAttributes:nil] autorelease];
}

/*
 * Returns the bundle version.
 */
- (NSString *)bundleVersion {
	return [self.myBundle objectForInfoDictionaryKey:@"CFBundleVersion"];
}

/*
 * Array of readable descriptions of the secret keys.
 */
- (NSArray *)secretKeyDescriptions {
	NSArray *keys = self.secretKeys;
	NSMutableArray *decriptions = [NSMutableArray arrayWithCapacity:[keys count]];
	for (GPGKey *key in keys) {
		[decriptions addObject:[NSString stringWithFormat:@"%@ – %@", key.userID, key.shortKeyID]];
	}
	return decriptions;
}

/*
 * Index of the default key.
 */
- (NSInteger)indexOfSelectedSecretKey {
	NSString *defaultKey = [options valueForKey:@"default-key"];
	if ([defaultKey length] == 0) {
		return -1;
	}
	
	NSArray *keys = self.secretKeys;
	
	NSInteger i, count = [keys count];
	for (i = 0; i < count; i++) {
		GPGKey *key = [keys objectAtIndex:i];
		if ([key.textForFilter rangeOfString:defaultKey options:NSCaseInsensitiveSearch].length > 0) {
			return i;
		}		
	}
	
	return -1;
}
- (void)setIndexOfSelectedSecretKey:(NSInteger)index {
	NSArray *keys = self.secretKeys;
	if (index < [keys count] && index >= 0) {
		[options setValue:[[keys objectAtIndex:index] fingerprint] forKey:@"default-key"];
	}
    else if (index == -1) {
		[options setValue:nil forKey:@"default-key"];
    }
}

- (IBAction)unsetDefaultKey:(id)sender {
    [self setIndexOfSelectedSecretKey:-1];
}


/*
 * Keyserver
 */
- (NSArray *)keyservers {
    return [options keyservers];
}

- (NSString *)keyserver {
    return [options valueForKey:kKeyserver];
}

- (void)setKeyserver:(NSString *)keyserver {
    [options setValue:keyserver forKey:kKeyserver];
    
    NSArray *autoklOptions = [options valueForKey:kAutoKeyLocate];
    if (!autoklOptions || ![autoklOptions containsObject:kKeyserver]) {
        NSMutableArray *newOptions = [NSMutableArray array];
        if (autoklOptions)
            [newOptions addObjectsFromArray:autoklOptions];
        [newOptions insertObject:kKeyserver atIndex:0];
        [options setValue:newOptions forKey:kAutoKeyLocate];
    }
}

+ (NSSet *)keyPathsForValuesAffectingKeyservers {
	return [NSSet setWithObject:@"options.keyservers"];
}
+ (NSSet *)keyPathsForValuesAffectingKeyserver {
	return [NSSet setWithObject:@"options.keyserver"];
}

- (IBAction)removeKeyserver:(id)sender {
	NSString *oldServer = self.keyserver;
	[self.options removeKeyserver:oldServer];
	NSArray *servers = self.keyservers;
	if (servers.count > 0) {
		if (![servers containsObject:oldServer]) {
			self.keyserver = [self.keyservers objectAtIndex:0];
		}
	} else {
		self.keyserver = @"";
	}
}



@end
