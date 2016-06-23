//
//  ExploreProject.m
//  Explore Prototype
//
//  Created by Alex Shepard on 10/2/14.
//  Copyright (c) 2014 iNaturalist. All rights reserved.
//

#import "ExploreProject.h"

@implementation ExploreProject

+ (NSDictionary *)JSONKeyPathsByPropertyKey{
    return @{
             @"title": @"title",
             @"projectId": @"id",
             @"locationId": @"place_id",
             @"latitude": @"latitude",
             @"longitude": @"longitude",
             @"iconUrl": @"icon_url",
             };
}

+ (NSValueTransformer *)iconUrlJSONTransformer {
    return [NSValueTransformer valueTransformerForName:MTLURLValueTransformerName];
}


@end
