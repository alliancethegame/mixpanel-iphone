//
//  SYArrayFilterTemplate.m
//  Shelley
//
//  Created by Pete Hodgson on 8/25/11.
//  Copyright 2011 ThoughtWorks. All rights reserved.
//

#import "SYFilters.h"

@implementation SYArrayFilterTemplate

// hook method, must be implemented by concrete subclass
- (NSArray *) applyToView:(ShelleyView *)view {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (NSArray *) applyToViews:(NSArray *)views {
    NSMutableArray *filteredViews = [NSMutableArray array];
    for (ShelleyView *view in views) {
        [filteredViews addObjectsFromArray:[self applyToView:view]];
    }    
    return filteredViews;
}

// default implementation ignores this directive, may be implemented by subclass
- (void)setDoNotDescend:(BOOL)doNotDescend {
}

// default implementation may be implemented by subclass
- (BOOL) nextFilterShouldNotDescend {
    return NO;
}

@end
//
//  SYClassFilter.m
//  Shelley
//
//  Created by Pete Hodgson on 7/22/11.
//  Copyright 2011 ThoughtWorks. All rights reserved.
//

#if !TARGET_OS_IPHONE
@interface NSApplication (FrankAutomation)
- (NSSet*) FEX_menus;
@end
#endif

@implementation SYClassFilter
@synthesize target=_targetClass;

+ (NSArray *) allDescendantsOf:(ShelleyView *)view{
    NSMutableArray *descendants = [NSMutableArray array];
    
#if TARGET_OS_IPHONE
    for (ShelleyView *subview in [view subviews]) {
        [descendants addObject:subview];
        [descendants addObjectsFromArray:[self allDescendantsOf:subview]];
    }
#else
    if ([view respondsToSelector: @selector(FEX_children)])
    {
        for (id child in [view performSelector: @selector(FEX_children)])
        {
            [descendants addObject: child];
            [descendants addObjectsFromArray: [self allDescendantsOf: child]];
        }
    }
    
#endif
    return descendants;
}

- (id)initWithClass:(Class)class {
#if TARGET_OS_IPHONE
    return [self initWithClass:class includeSelf:NO];
#else
    return [self initWithClass:class includeSelf:YES];
#endif
}

- (id)initWithClass:(Class)class includeSelf:(BOOL)includeSelf {
    self = [super init];
    if (self) {
        _targetClass = class;
		_includeSelf = includeSelf;
        _justFilter = NO;
    }
    return self;
}

- (void)setDoNotDescend:(BOOL)doNotDescend {
    _justFilter = doNotDescend;
}

-(NSArray *)viewsToConsiderFromView:(ShelleyView *)view{
    if( _justFilter )
        return [NSArray arrayWithObject:view];
    
    NSMutableArray *allViews = _includeSelf ? [NSMutableArray arrayWithObject:view] : [NSMutableArray array];
    [allViews addObjectsFromArray:[SYClassFilter allDescendantsOf:view]];
    return allViews;
}


-(NSArray *)applyToView:(ShelleyView *)view{
    NSArray *allViews = [self viewsToConsiderFromView:view];
	
    // TODO: look at using predicates
    NSMutableArray *filteredDescendants = [NSMutableArray array];
    for (ShelleyView *v in allViews) {
        if( [v isKindOfClass:_targetClass] ){
            [filteredDescendants addObject:v];
        }
    }
    
    return filteredDescendants;
}

@end
//
//  SYNthElementFilter.m
//  Shelley
//
//  Created by Pete Hodgson on 8/25/11.
//  Copyright 2011 ThoughtWorks. All rights reserved.
//


@implementation SYNthElementFilter
@synthesize index=_index;

- (id)initWithIndex:(NSUInteger)index {
    self = [super init];
    if (self) {
        _index = index;
    }
    return self;
}

- (NSArray *)applyToViews:(NSArray *)views {
    if( [views count] > _index )
        return [NSArray arrayWithObject:[views objectAtIndex:_index]];
    else
        return [NSArray array];
}

- (void)setDoNotDescend:(BOOL)doNotDescend {
    // ignored
}

- (BOOL) nextFilterShouldNotDescend {
    return NO;
}

@end
//
//  SYParents.m
//  Shelley
//
//  Created by Pete Hodgson on 7/20/11.
//  Copyright 2011 ThoughtWorks. All rights reserved.
//


@implementation SYParents

-(NSArray *)applyToView:(ShelleyView *)view{
    NSMutableArray *ancestors = [NSMutableArray array];
    
#if TARGET_OS_IPHONE
    ShelleyView *currentView = view;
    
    while(( currentView = [currentView superview] )){
        [ancestors addObject:currentView];
    }
#else
    id currentView = view;
    
    while (currentView != nil) {
        if ([currentView respondsToSelector: @selector(FEX_parent)])
        {
            currentView = [currentView performSelector: @selector(FEX_parent)];
        }
        else
        {
            currentView = nil;
        }
        
        if (currentView != nil) {
            [ancestors addObject: currentView];
        }
    }
    
#endif
    
    return ancestors;
}

- (BOOL) nextFilterShouldNotDescend {
    return YES;
}

@end
//
//  SYPredicateFilter.m
//  Shelley
//
//  Created by Pete Hodgson on 7/20/11.
//  Copyright 2011 ThoughtWorks. All rights reserved.
//

@implementation SYPredicateFilter
@synthesize selector=_selector,args=_args;

- (id)initWithSelector:(SEL)selector args:(NSArray *)args {
    self = [super init];
    if (self) {
        _selector = selector;
        _args = [args copy];
    }
    return self;
}

- (void)castNumber:(NSNumber *)number toType:(const char*)objCType intoBuffer:(void *)buffer{
	// specific cases should be added here as needed
	if( !strcmp(objCType, @encode(int)) ){
		*((int *)buffer) = [number intValue];
	}else if( !strcmp(objCType, @encode(uint)) ){
		*((uint *)buffer) = [number unsignedIntValue];
	}else {
		NSLog(@"Didn't know how to convert NSNumber to type %s", objCType); 
	}	
}

- (NSInvocation *) createInvocationForObject:(id)object{
    NSMethodSignature *signature = [object methodSignatureForSelector:_selector];
    if( !signature )
        return nil;
    
    if( strcmp([signature methodReturnType], @encode(BOOL)) ){
        [NSException raise:@"wrong return type" 
					format:@"predicate does not return a BOOL"];
    }
    
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    
    NSUInteger requiredNumberOfArguments = signature.numberOfArguments - 2; // Indices 0 and 1 indicate the hidden arguments self and _cmd, respectively
	if( requiredNumberOfArguments != [_args count] )
#if TARGET_OS_IPHONE
		[NSException raise:@"wrong number of arguments"
					format:@"%@ takes %i arguments, but %i were supplied", NSStringFromSelector(_selector), requiredNumberOfArguments, [_args count] ];
#else
    [NSException raise:@"wrong number of arguments"
                format:@"%@ takes %li arguments, but %li were supplied", NSStringFromSelector(_selector), requiredNumberOfArguments, [_args count] ];
#endif
	
	[invocation setSelector:_selector];
	
	char invocationBuffer[300]; //let's hope we don't get asked to invoke a method with more than 28 arguments.
	
	NSInteger index = 2; // Indices 0 and 1 indicate the hidden arguments self and _cmd, respectively
	for( __unsafe_unretained id arg in _args ) {
		if( [arg isKindOfClass:[NSNumber class]] ){
			void *buffer = &(invocationBuffer[index*10]);
			[self castNumber:arg toType:[signature getArgumentTypeAtIndex:index] intoBuffer:buffer];
			[invocation setArgument:buffer atIndex:index];
		}else {
			[invocation setArgument:&arg atIndex:index];
		}
		index++;
	}
    
    return invocation;
}

- (BOOL) extractBooleanReturnValueFromInvocation:(NSInvocation *)invocation{
    BOOL retval;
    [invocation getReturnValue:&retval];
    return retval;
}

-(NSArray *)applyToView:(ShelleyView *)view{
    NSInvocation *invocation = [self createInvocationForObject:view];
    if( !invocation )
        return [NSArray array];
     
    [invocation invokeWithTarget:view];
    BOOL predicatePassed = [self extractBooleanReturnValueFromInvocation:invocation];
    
    if( predicatePassed )
        return [NSArray arrayWithObject:view];
    else
        return [NSArray array];
}

@end