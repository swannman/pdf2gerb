#Pdf2Gerb config settings:
#Put this file in same folder/directory as pdf2gerb.pl itself (global settings),
#or copy to another folder/directory with PDFs if you want PCB-specific settings.
#There is only one user of this file, so we don't need a custom package or namespace.
#NOTE: all constants defined in here will be added to main namespace.
#package pdf2gerb_cfg;

use strict; #trap undef vars (easier debug)
use warnings; #other useful info (easier debug)


##############################################################################################
#configurable settings:
#change values here instead of in main pfg2gerb.pl file

use constant WANT_COLORS => ($^O !~ m/Win/); #ANSI colors no worky on Windows? this must be set < first DebugPrint() call

#just a little warning; set realistic expectations:
#DebugPrint("${\(CYAN)}Pdf2Gerb.pl ${\(VERSION)}, $^O O/S\n${\(YELLOW)}${\(BOLD)}${\(ITALIC)}This is EXPERIMENTAL software.  \nGerber files MAY CONTAIN ERRORS.  Please CHECK them before fabrication!${\(RESET)}", 0); #if WANT_DEBUG

use constant METRIC => FALSE; #set to TRUE for metric units (only affect final numbers in output files, not internal arithmetic)
use constant APERTURE_LIMIT => 0; #34; #max #apertures to use; generate warnings if too many apertures are used (0 to not check)
use constant DRILL_FMT => '2.4'; #'2.3'; #'2.4' is the default for PCB fab; change to '2.3' for CNC

use constant WANT_DEBUG => 0; #10; #level of debug wanted; higher == more, lower == less, 0 == none
use constant GERBER_DEBUG => 0; #level of debug to include in Gerber file; DON'T USE FOR FABRICATION
use constant WANT_STREAMS => FALSE; #TRUE; #save decompressed streams to files (for debug)
use constant WANT_ALLINPUT => FALSE; #TRUE; #save entire input stream (for debug ONLY)

#DebugPrint(sprintf("${\(CYAN)}DEBUG: stdout %d, gerber %d, want streams? %d, all input? %d, O/S: $^O, Perl: $]${\(RESET)}\n", WANT_DEBUG, GERBER_DEBUG, WANT_STREAMS, WANT_ALLINPUT), 1);
#DebugPrint(sprintf("max int = %d, min int = %d\n", MAXINT, MININT), 1); 

#define standard trace and pad sizes to reduce scaling or PDF rendering errors:
#This avoids weird aperture settings and replaces them with more standardized values.
#(I'm not sure how photoplotters handle strange sizes).
#Fewer choices here gives more accurate mapping in the final Gerber files.
#units are in inches
use constant TOOL_SIZES => #add more as desired
(
#round or square pads (> 0) and drills (< 0):
    .010, -.001,  #tiny pads for SMD; dummy drill size (too small for practical use, but needed so StandardTool will use this entry)
    .031, -.014,  #used for vias
    .041, -.020,  #smallest non-filled plated hole
    .051, -.025,
    .056, -.029,  #useful for IC pins
    .070, -.033,
    .075, -.040,  #heavier leads
#    .090, -.043,  #NOTE: 600 dpi is not high enough resolution to reliably distinguish between .043" and .046", so choose 1 of the 2 here
    .100, -.046,
    .115, -.052,
    .130, -.061,
    .140, -.067,
    .150, -.079,
    .175, -.088,
    .190, -.093,
    .200, -.100,
    .220, -.110,
    .160, -.125,  #useful for mounting holes
#some additional pad sizes without holes (repeat a previous hole size if you just want the pad size):
    .090, -.040,  #want a .090 pad option, but use dummy hole size
    .065, -.040, #.065 x .065 rect pad
    .035, -.040, #.035 x .065 rect pad
#traces:
    .001,  #too thin for real traces; use only for board outlines
    .006,  #minimum real trace width; mainly used for text
    .008,  #mainly used for mid-sized text, not traces
    .010,  #minimum recommended trace width for low-current signals
    .012,
    .015,  #moderate low-voltage current
    .020,  #heavier trace for power, ground (even if a lighter one is adequate)
    .025,
    .030,  #heavy-current traces; be careful with these ones!
    .040,
    .050,
    .060,
    .080,
    .100,
    .120,
);
#Areas larger than the values below will be filled with parallel lines:
#This cuts down on the number of aperture sizes used.
#Set to 0 to always use an aperture or drill, regardless of size.
use constant { MAX_APERTURE => max((TOOL_SIZES)) + .004, MAX_DRILL => -min((TOOL_SIZES)) + .004 }; #max aperture and drill sizes (plus a little tolerance)
#DebugPrint(sprintf("using %d standard tool sizes: %s, max aper %.3f, max drill %.3f\n", scalar((TOOL_SIZES)), join(", ", (TOOL_SIZES)), MAX_APERTURE, MAX_DRILL), 1);

#NOTE: Compare the PDF to the original CAD file to check the accuracy of the PDF rendering and parsing!
#for example, the CAD software I used generated the following circles for holes:
#CAD hole size:   parsed PDF diameter:      error:
#  .014                .016                +.002
#  .020                .02267              +.00267
#  .025                .026                +.001
#  .029                .03167              +.00267
#  .033                .036                +.003
#  .040                .04267              +.00267
#This was usually ~ .002" - .003" too big compared to the hole as displayed in the CAD software.
#To compensate for PDF rendering errors (either during CAD Print function or PDF parsing logic), adjust the values below as needed.
#units are pixels; for example, a value of 2.4 at 600 dpi = .0004 inch, 2 at 600 dpi = .0033"
use constant
{
    HOLE_ADJUST => -0.004 * 600, #-2.6, #holes seemed to be slightly oversized (by .002" - .004"), so shrink them a little
    RNDPAD_ADJUST => -0.003 * 600, #-2, #-2.4, #round pads seemed to be slightly oversized, so shrink them a little
    SQRPAD_ADJUST => +0.001 * 600, #+.5, #square pads are sometimes too small by .00067, so bump them up a little
    RECTPAD_ADJUST => 0, #(pixels) rectangular pads seem to be okay? (not tested much)
    TRACE_ADJUST => 0, #(pixels) traces seemed to be okay?
    REDUCE_TOLERANCE => .001, #(inches) allow this much variation when reducing circles and rects
};

#Also, my CAD's Print function or the PDF print driver I used was a little off for circles, so define some additional adjustment values here:
#Values are added to X/Y coordinates; units are pixels; for example, a value of 1 at 600 dpi would be ~= .002 inch
use constant
{
    CIRCLE_ADJUST_MINX => 0,
    CIRCLE_ADJUST_MINY => -0.001 * 600, #-1, #circles were a little too high, so nudge them a little lower
    CIRCLE_ADJUST_MAXX => +0.001 * 600, #+1, #circles were a little too far to the left, so nudge them a little to the right
    CIRCLE_ADJUST_MAXY => 0,
    SUBST_CIRCLE_CLIPRECT => FALSE, #generate circle and substitute for clip rects (to compensate for the way some CAD software draws circles)
    WANT_CLIPRECT => TRUE, #FALSE, #AI doesn't need clip rect at all? should be on normally?
    RECT_COMPLETION => FALSE, #TRUE, #fill in 4th side of rect when 3 sides found
};

#allow .012 clearance around pads for solder mask:
#This value effectively adjusts pad sizes in the TOOL_SIZES list above (only for solder mask layers).
use constant SOLDER_MARGIN => +.012; #units are inches

#line join/cap styles:
use constant
{
    CAP_NONE => 0, #butt (none); line is exact length
    CAP_ROUND => 1, #round cap/join; line overhangs by a semi-circle at either end
    CAP_SQUARE => 2, #square cap/join; line overhangs by a half square on either end
    CAP_OVERRIDE => FALSE, #cap style overrides drawing logic
};
    
#number of elements in each shape type:
use constant
{
    RECT_SHAPELEN => 6, #x0, y0, x1, y1, count, "rect" (start, end corners)
    LINE_SHAPELEN => 6, #x0, y0, x1, y1, count, "line" (line seg)
    CURVE_SHAPELEN => 10, #xstart, ystart, x0, y0, x1, y1, xend, yend, count, "curve" (bezier 2 points)
    CIRCLE_SHAPELEN => 5, #x, y, 5, count, "circle" (center + radius)
};
#const my %SHAPELEN =
#Readonly my %SHAPELEN =>
our %SHAPELEN =
(
    rect => RECT_SHAPELEN,
    line => LINE_SHAPELEN,
    curve => CURVE_SHAPELEN,
    circle => CIRCLE_SHAPELEN,
);

#panelization:
#This will repeat the entire body the number of times indicated along the X or Y axes (files grow accordingly).
#Display elements that overhang PCB boundary can be squashed or left as-is (typically text or other silk screen markings).
#Set "overhangs" TRUE to allow overhangs, FALSE to truncate them.
#xpad and ypad allow margins to be added around outer edge of panelized PCB.
use constant PANELIZE => {'x' => 1, 'y' => 1, 'xpad' => 0, 'ypad' => 0, 'overhangs' => TRUE}; #number of times to repeat in X and Y directions

# Set this to 1 if you need TurboCAD support.
#$turboCAD = FALSE; #is this still needed as an option?

#CIRCAD pad generation uses an appropriate aperture, then moves it (stroke) "a little" - we use this to find pads and distinguish them from PCB holes. 
use constant PAD_STROKE => 0.3; #0.0005 * 600; #units are pixels
#convert very short traces to pads or holes:
use constant TRACE_MINLEN => .001; #units are inches
#use constant ALWAYS_XY => TRUE; #FALSE; #force XY even if X or Y doesn't change; NOTE: needs to be TRUE for all pads to show in FlatCAM and ViewPlot
use constant REMOVE_POLARITY => FALSE; #TRUE; #set to remove subtractive (negative) polarity; NOTE: must be FALSE for ground planes

#PDF uses "points", each point = 1/72 inch
#combined with a PDF scale factor of .12, this gives 600 dpi resolution (1/72 * .12 = 600 dpi)
use constant INCHES_PER_POINT => 1/72; #0.0138888889; #multiply point-size by this to get inches

# The precision used when computing a bezier curve. Higher numbers are more precise but slower (and generate larger files).
#$bezierPrecision = 100;
use constant BEZIER_PRECISION => 36; #100; #use const; reduced for faster rendering (mainly used for silk screen and thermal pads)

# Ground planes and silk screen or larger copper rectangles or circles are filled line-by-line using this resolution.
use constant FILL_WIDTH => .01; #fill at most 0.01 inch at a time

# The max number of characters to read into memory
use constant MAX_BYTES => 10 * M; #bumped up to 10 MB, use const

use constant DUP_DRILL1 => TRUE; #FALSE; #kludge: ViewPlot doesn't load drill files that are too small so duplicate first tool

my $runtime = time(); #Time::HiRes::gettimeofday(); #measure my execution time

print STDERR "Loaded config settings from '${\(__FILE__)}'.\n";
1; #last value must be truthful to indicate successful load


#############################################################################################
#junk/experiment:

#use Package::Constants;
#use Exporter qw(import); #https://perldoc.perl.org/Exporter.html

#my $caller = "pdf2gerb::";

#sub cfg
#{
#    my $proto = shift;
#    my $class = ref($proto) || $proto;
#    my $settings =
#    {
#        $WANT_DEBUG => 990, #10; #level of debug wanted; higher == more, lower == less, 0 == none
#    };
#    bless($settings, $class);
#    return $settings;
#}

#use constant HELLO => "hi there2"; #"main::HELLO" => "hi there";
#use constant GOODBYE => 14; #"main::GOODBYE" => 12;

#print STDERR "read cfg file\n";

#our @EXPORT_OK = Package::Constants->list(__PACKAGE__); #https://www.perlmonks.org/?node_id=1072691; NOTE: "_OK" skips short/common names

#print STDERR scalar(@EXPORT_OK) . " consts exported:\n";
#foreach(@EXPORT_OK) { print STDERR "$_\n"; }
#my $val = main::thing("xyz");
#print STDERR "caller gave me $val\n";
#foreach my $arg (@ARGV) { print STDERR "arg $arg\n"; }
