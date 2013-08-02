#import <Cocoa/Cocoa.h>
#ifdef __OPTIMIZE__
#include <sys/ptrace.h>
#endif

int main(int argc, char *argv[])
{
#ifdef __OPTIMIZE__
	ptrace(PT_DENY_ATTACH, 0, 0, 0);
#endif
    return NSApplicationMain(argc, (const char **) argv);
}
