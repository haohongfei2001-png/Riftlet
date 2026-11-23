#define main native_preparation_main
#import "ax_prepare.m"
#undef main
int main(void) {
  @autoreleasepool {
    require(typingCaret(CFRangeMake(0,0)) && !typingCaret(CFRangeMake(1,0)) && !typingCaret(CFRangeMake(0,1)),"ZERO_CARET_REQUIRED");
    require([draft length]==64 && [[draft componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet] count]==1,"FIXED_PRINTABLE_SENTENCE");
    require([displayClass(@"",nil,nil) isEqual:@"empty"],"EMPTY");
    require([displayClass([[NSAttributedString alloc] initWithString:@"\n"],nil,nil) isEqual:@"emptyBlock"],"EMPTY_BLOCK");
    require([displayClass(@"sample",@"sample",nil) isEqual:@"sameAsAXPlaceholder"],"MIRRORED_PROMPT");
    require([displayClass(@"sample",@"other",nil) isEqual:@"other"],"ARBITRARY_VALUE");
    require([displayClass(nil,nil,@0) isEqual:@"unexposedZeroChars"],"ZERO_CHARACTERS");
    require([displayClass(nil,nil,nil) isEqual:@"unexposed"],"NO_EMPTY_PROOF");
    require([displayClass([draft stringByAppendingString:@"\n"],nil,nil) isEqual:@"expected"],"TRAILING_PARAGRAPH");
  }
  return 0;
}
