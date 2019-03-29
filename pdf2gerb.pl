#!/usr/bin/perl
# pdf2gerb 1.6p
#
# (c) 2010 Matthew M. Swann, swannman@mac.com - initial versions
# (c) 2012-2016,2019 djulien17@thejuliens.net (1.5 + 1.6) - I offer up these enhancements to our Grand Designer, and hoping to make it easier for other hobbyists to create PCBs.
# (c) 2019 Clem Ong - mods for CIRCAD v5 PDFs (use "ps to PDF file" output in Circad, then run this program to get your gerbers)
#
# Rev history:
# Version  Date     Who  What
# 1.4      7/2011   MS   last public version from Matt
# 1.5a     4/7/12   DJ   add support for PDF 1.4 compression (flate decode)
# 1.5b     4/9/12   DJ   handle scale transform (was giving incorrect dimensions), warn about file too big and use consts (seems safer)
# 1.5c     4/10/12  DJ   fix filled circles, change drill fmt to 2.4 (drill coords were interpreted as 10x)
# 1.5d     4/11/12  DJ   set origin to lower left corner of PCB, draw large circles on silk screen using line segments
# 1.5e     4/12/12  DJ   use rectangular apertures for square/rectangular pads, accept multiple files (top + bottom + silk screen) and concatenate to look like 1 file with multiple layers, update usage message
# 1.5f     4/14/12  DJ   fix "." and \s in regex, added G04 for easier debug, add inverted/filled areas (layer polarity), placeholders for top + bottom solder masks
# 1.5g     4/20/12  DJ   restructured drawing loop to handle multiple stoke vs. fill commands (to support thermal pads, ground planes, solder masks), restructured main line code, only emit tool commands when needed, turned on strict + warnings, explicitly declare locals/globals ("my", "our")
# 1.5h     4/24/12  DJ   map scaled aperture and trace sizes to standard values, consolidate hole lists to minimize drill tool swapping, change aperture lists to use hash (faster lookups), undo larger holes if smaller hole found in same location
# 1.5i     4/25/12  DJ   generate solder masks (invert + enlarge all pads, no holes)
# 1.5j     4/28/12  DJ   added polygon fill (needed for ground plane and no-fill areas), allow metric units for non-US people
# 1.5k     5/1/12   DJ   added panelization; fixed polygon fill (nudge edges for more accurate edges); generate separate outline layer
# 1.6      5/5/12   DJ   misc fixes, released for testing
# 1.6a     5/6/12   DJ   trim panel overhangs even with 1 x 1 (by default), added some pad/hole sizes, allow rotated PDFs (landscape prints), allow x + y pad around panelization
# 1.6b     5/21/12  DJ   pre-scan multiple layers for PCB outline, don't use clip rect for outline, generate drill file on any layer (for Matt's test file)
# 1.6c     1/7/13   DJ   initialize visibility to Tristate value so both holes + pads will be recognized if no fill/stroke color set in PDF, treat singleton layer as copper, not silk
# 1.6d     1/30/13  DJ   insert dummy G54D10 command at start, in case there are no traces (avoids ViewPlot D00 message for outline file)
# 1.6e     2/1/13   DJ   added DRILL_FMT to allow 2.3 or 2.4 drill format, show version# in output files
# 1.6f     3/21/13  DJ   made \n after "stream" optional (newer PDFCreator omits it?); default WANT_STREAMS to FALSE; extract max 100 streams (for safety); use REDUCE_TOLERANCE const for adjustable tolerance on reduce logic
# 1.6g     3/28/13  GDM/DJ implement gray space drawing attr; change "\1" to "$1" to prevent perl warning; substitute circles for clip rects (SUBST_CIRCLE_CLIPRECT)
# 1.6h     4/11/13  DJ   allow \r\n between "<<" and "/FlateDecode"; make \n optional between commands; join commands that are split across lines; added more debug; force input to Unicode
# 1.6i     7/14/14  DJ   avoid /0 error for nudge line segment or polygon edge, avoid infinite loops for outline/fill unknown shapes, fix handling of 2 adjacent polygon edges parallel (shouldn't happen, though)
# 1.6j     9/30/15  DJ   fix an additional subscript error; perl short-circuit IF doesn't seem to be working
# 1.6k     1/2/16   DJ   undo attempt to compensate for Unicode; broke parser logic
# 1.6L     1/24/16  DJ   handle "re W" on same line, draw/fill bezier curves on silk screen (fill requires additional module), allow stand-alone line fill, add placeholder for curve offset
# 1.6m     4/12/16  DJ   add a little info into warnings about the command being ignored; add WANT_CLIPRECT parameter to disable clip rect (turn off for AI example); detect AI; don't change origin for AI; fix uninit vars; fix Flate 1.3 decompress; *AI example files should work now*
# 1.6n     2/16/19  DJ   avoid dup line draws, store line join/cap styles, convert short traces to pads/holes (cap style selects round/square aperture), show command line args with usage, smarter default file names/types/ordering/counting, add console color to a few messages
# 1.6L3h - Experimental: attempt to get this working with Circad 4 and 5. Clem
#   Working:   Holes and through-hole pads (square and round) are routed to fill();
#              Solder mask for through-hole Square pads
#              SMD pads are generated properly by outline() now by adding recognition of line cap style (1J and 2J)
#   Not Working:  Solder mask for through-hole round pad: diameter too small - can't find where it goes wrong...
#                 SMD pads do not have any mask (because the pads are generated by outline(), which is meant to generate tracks in general)
#                     -- can't get SMD pads to work with fill() properly...
#                * IF masks are unimportant, this program might already be OK (i.e Gerbv visual looks good)
#                             --> for further testing and verification on more complex boards
#                * Required work: calibration of fudge factors, Adding/Modifying required drill sizes, pad sizes, track widths
# 1.6L3i - modded fill() to address round pad mask, using DJ's code from v1.6n
#            - forced $visibleFillColor(f) FALSE or TRUE for holes and pads, respectively
#			 - pad detect: increased move tolerance to "0.3" to cover all pads
#   Fixed: 	  Solder mask for through-hole Square and Round pads
#             Pad detection and generation
# 1.6L3j   2/23/19  CYO  mods for CIRCAD Omniglyph v5 PDF output; FlatCAM v8.9 gerber compatibility.  Should work too with Circad v4.2
#                       **** NOTE: this version is for internal use only as it hasn't been tested for compatibility with other PCB software ****
# 1.6L3j - fixed FlatCAM incompatibility:
#              Added routine to strip copper gerber output of "noise" commands consisting of triplet lines as:
#                 %LPC*%
#                 G54Dxxx
#                 G04 xxx
#              -> these 3 lines do not have any effect on a Gerber... (but produces odd pad sizes/shapes with FlatCAM)
# 1.6o     2/24/19  CYO/DJ  (merged) fix round pad mask, fix FlatCAM incompatibility, put at least 2 apertures in DRD file (ViewPlot doesn't load DRD file with only 1 drill); fix spurious trace in open polygon (add RECT_COMPLETION option)
# 1.6p     3/4-12/19  CYO/DJ  fix reduceRect *again* (generated spurious trace), use first layer title for output filenames, fix up output file names *again*, don't ignore embedded streams if no title found, fix stripNoise
# 1.6q     3/16-25/19  CYO/DJ  fix trace size on non-converted pads, fix missing pads (only affected display in FlatCAM and ViewPlot, GerbView was only), fix stream processing with only 1 layer, fix missing shapes (older regression), do the stroke part of stroke-and-fill (ignore fill), add CAP_OVERRIDE option so older test files will still work, fix groundplanes (polyfill regression), first try at moving config consts to separate file, fix layer desc chooser again (SMD copper layers don't have holes), added tiny tool size for SMD example file
#
#
# Notes/Current limitations:
# - PCB outline is assumed to be rectangular
# - Holes in PDFs must be white circles; copper areas any color except white
# - Some CAD packages have origin in top left, but PDF is bottom left
# - Polygons and larger pads are filled with .001" lines; for non-rectangular ground planes, any points and intersections will be at least this wide (even if source CAD software shows them as points).
# - Polygons (ground planes) where the edges define internal "cut-out" areas will be treated as such, even if the CAD software fills them.
# - Larger pads that are filled will not have a solder mask opening (we don't want a solder mask opening on ground planes, for example).
# - Panelization will squash text or other display elements outside the PCB border to avoid interference with adjacent panels (by design).
# - FlatCAM gerber processing has a bug - once a tool of larger diameter is used to draw a pad, the
#                                         program will NOT go to a smaller tool diameter despite being told to - thus pads will remain at the
#                                         largest tool diameter, until a larger one comes along (if there is one).
#
#
# TODO maybe:
# -elliptical pads? (draw short line seg using round aperture)
# -use G02/03/75 circular commands instead of drawing circles with line segments?
# -use hollow apertures? (pads are currently solid circles and hole is in center; this seems okay)
# -make it run faster? (not too bad now)
# -add command-line parameters or config file instead of editing config constants?
# -use line cap + join styles for all lines? (butt/round/square)
# -exclude selected layers?
#
#
# Helpful background links:
# (Gerber)
# Gerber intro:  http://www.apcircuits.com/resources/information/gerber_data.html
# G-codes + D-codes:  http://www.artwork.com/gerber/appl2.htm
# 274X format:  http://www.artwork.com/gerber/274x/rs274x.htm
# KiCAD Gerbers:  http://www.kxcad.net/visualcam/visualcam/tutorials/gerber_for_beginners.htm
# Excellon (drill file):  http://www.excellon.com/manuals/program.htm
# Creating Gerbers:  http://www.sparkfun.com/tutorials/109
# Gerbv (viewer):  http://gerbv.gpleda.org/index.html
# Viewplot (viewer):  http://www.viewplot.com  (seems to work best with files in this order: drill gray, bottom mask, bottom copper red, top mask, top copper green, silk blue, outline)
# Pdf2Gerb:  http://swannman.github.com/pdf2gerb/
# (Other)
# Cubic Bezier curves for circles:  http://www.tinaja.com/glib/ellipse4.pdf
# Polygon fill algorithm:  http://alienryderflex.com/polygon_fill/
# Point-in-polygon algoritm:  http://alienryderflex.com/polygon/
# Perl help:  http://www.perlmonks.org 
# PDF ref: https://www.adobe.com/content/dam/acom/en/devnet/pdf/pdfs/pdf_reference_archives/PDFReference.pdf
# PDFCreator 1.3.2 (CAREFUL: TURN OFF SPYWARE DURING INSTALL):  http://sourceforge.net/projects/pdfcreator/
# Strawberry Perl (for Windows):  http://www.strawberryperl.com
# Perl debugging: https://perldoc.perl.org/perldebtut.html
#  list installed Perl modules: cpan -a
#
# More information about this work can be found at the following URL:
# http://swannman.github.com/pdf2gerb/
#
# This work is released under the terms and conditions set forth under
# the GNU General Public License 3.0.  For more details, see the following:
# http://www.gnu.org/licenses/gpl-3.0.txt
#
###########################################################################
use strict; #trap undef vars, etc (easier debug)
use warnings; #other useful info (easier debug)

use Cwd; #gets current directory
use Compress::Zlib; #needed for PDF1.4 decompression
use File::Spec; #Path::Class; #for folder/directory name manipulation
use Time::HiRes qw(time); #for elapsed time calculation
use List::Util qw(min max); #[min max];
use Encode; #::Detect::Detector; #for detecting charset encoding
#use Math::Bezier; #http://search.cpan.org/~abw/Math-Bezier-0.01/Bezier.pm
use List::MoreUtils qw(first_index);
use Term::ANSIColor qw(:constants); #console color codes
use Term::ANSIColor 2.01 qw(colorstrip); #remove colors; https://perldoc.perl.org/Term/ANSIColor.html
#not found :( use Const::Fast; #https://stackoverflow.com/questions/4370058/hash-constants-in-perl
#use Readonly;
use File::Basename; #https://perldoc.perl.org/File/Basename.html

#are fwd defs needed?
#sub inches; #ToInches;
#sub inchesX;
#sub inchesY;
#sub ToDrillInches;
#sub GetAperture;
#sub GetDrillAperture;
#sub ComputeBezier;
#sub DebugPrint;
#sub FillRect;
#sub SetPolarity;
##sub min;
##sub max;

#printf STDERR "me at " . __FILE__ . "\n";
#print STDERR "my dir " . dirname(__FILE__) . "\n";
#package pdf2gerb; #CAUTION: renames other subs found in this file
#print STDERR "i am at " . $INC{$_} . "\n";
use constant VERSION => '1.6q';

#Perl constants can be optimized at compile time (as inlined functions), so here are some:
#DON'T CHANGE THESE
use constant { TRUE => 1, FALSE => 0, MAYBE => 2 }; #tri-state values
use constant { MININT => - 2 ** 31 - 1, MAXINT => 2 ** 31 - 1}; #big enough for simple arithmetic purposes
use constant { K => 1024, M => 1024 * 1024 }; #used for more concise display of numbers
use constant PI => 4 * atan2(1, 1); #used for circumference calculations
if (!TRUE || FALSE) { die("bool consts broken"); }

##############################################################################################
#configurable settings:
#to change any constants below, edit the default pdf2gerb_cfg.pm file or make a copy in a subfolder/directory first
use lib dirname(__FILE__); #find packages in Pdf2Gerb folder/directory; https://stackoverflow.com/questions/728597/how-can-my-perl-script-find-its-module-in-the-same-directory
use lib "."; #allow local settings to override global settings; https://www.perlmonks.org/bare/?node_id=375341
use pdf2gerb_cfg; #read settings from separate file; check CWD first, then Pdf2Gerb folder/directory

#constants below were moved to pdf2gerb_cfg.pm:
#use constant WANT_COLORS => ($^O !~ m/Win/); #ANSI colors no worky on Windows? this must be set < first DebugPrint() call

#just a little warning; set realistic expectations:
DebugPrint("${\(CYAN)}Pdf2Gerb.pl ${\(VERSION)}, $^O O/S\n${\(YELLOW)}${\(BOLD)}${\(ITALIC)}This is EXPERIMENTAL software.  \nGerber files MAY CONTAIN ERRORS.  Please CHECK them before fabrication!${\(RESET)}", 0); #if WANT_DEBUG

#use constant METRIC => FALSE; #set to TRUE for metric units (only affect final numbers in output files, not internal arithmetic)
#use constant APERTURE_LIMIT => 0; #34; #max #apertures to use; generate warnings if too many apertures are used (0 to not check)
#use constant DRILL_FMT => '2.4'; #'2.3'; #'2.4' is the default for PCB fab; change to '2.3' for CNC

#use constant WANT_DEBUG => 990; #10; #level of debug wanted; higher == more, lower == less, 0 == none
#print STDERR "WANT_DEBUG = ${\(WANT_DEBUG)}\n"; exit();
#use constant GERBER_DEBUG => 0; #level of debug to include in Gerber file; DON'T USE FOR FABRICATION
#use constant WANT_STREAMS => FALSE; #TRUE; #save decompressed streams to files (for debug)
#use constant WANT_ALLINPUT => TRUE; #FALSE; #TRUE; #save entire input stream (for debug ONLY)

DebugPrint(sprintf("${\(CYAN)}DEBUG: stdout %d, gerber %d, want streams? %d, all input? %d, O/S: $^O, Perl: $]${\(RESET)}\n", WANT_DEBUG, GERBER_DEBUG, WANT_STREAMS, WANT_ALLINPUT), 1);
#DebugPrint(sprintf("max int = %d, min int = %d\n", MAXINT, MININT), 1); 

#define standard trace and pad sizes to reduce scaling or PDF rendering errors:
#This avoids weird aperture settings and replaces them with more standardized values.
#(I'm not sure how photoplotters handle strange sizes).
#Fewer choices here gives more accurate mapping in the final Gerber files.
#units are in inches
#use constant TOOL_SIZES => #add more as desired
#(
#round or square pads (> 0) and drills (< 0):
#    .010, -.001,  #tiny pads for SMD; dummy drill size (too small for practical use, but needed so StandardTool will use this entry)
#    .031, -.014,  #used for vias
#    .041, -.020,  #smallest non-filled plated hole
#    .051, -.025,
#    .056, -.029,  #useful for IC pins
#    .070, -.033,
#    .075, -.040,  #heavier leads
#    .090, -.043,  #NOTE: 600 dpi is not high enough resolution to reliably distinguish between .043" and .046", so choose 1 of the 2 here
#    .100, -.046,
#    .115, -.052,
#    .130, -.061,
#    .140, -.067,
#    .150, -.079,
#    .175, -.088,
#    .190, -.093,
#    .200, -.100,
#    .220, -.110,
#    .160, -.125,  #useful for mounting holes
#some additional pad sizes without holes (repeat a previous hole size if you just want the pad size):
#    .090, -.040,  #want a .090 pad option, but use dummy hole size
#    .065, -.040, #.065 x .065 rect pad
#    .035, -.040, #.035 x .065 rect pad
#traces:
#    .001,  #too thin for real traces; use only for board outlines
#    .006,  #minimum real trace width; mainly used for text
#    .008,  #mainly used for mid-sized text, not traces
#    .010,  #minimum recommended trace width for low-current signals
#    .012,
#    .015,  #moderate low-voltage current
#    .020,  #heavier trace for power, ground (even if a lighter one is adequate)
#    .025,
#    .030,  #heavy-current traces; be careful with these ones!
#    .040,
#    .050,
#    .060,
#    .080,
#    .100,
#    .120,
#);
#Areas larger than the values below will be filled with parallel lines:
#This cuts down on the number of aperture sizes used.
#Set to 0 to always use an aperture or drill, regardless of size.
#use constant { MAX_APERTURE => max((TOOL_SIZES)) + .004, MAX_DRILL => -min((TOOL_SIZES)) + .004 }; #max aperture and drill sizes (plus a little tolerance)
DebugPrint(sprintf("using %d standard tool sizes: %s, max aper %.3f, max drill %.3f\n", scalar((TOOL_SIZES)), join(", ", (TOOL_SIZES)), MAX_APERTURE, MAX_DRILL), 1);

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
#use constant
#{
#    HOLE_ADJUST => -0.004 * 600, #-2.6, #holes seemed to be slightly oversized (by .002" - .004"), so shrink them a little
#    RNDPAD_ADJUST => -0.003 * 600, #-2, #-2.4, #round pads seemed to be slightly oversized, so shrink them a little
#    SQRPAD_ADJUST => +0.001 * 600, #+.5, #square pads are sometimes too small by .00067, so bump them up a little
#    RECTPAD_ADJUST => 0, #(pixels) rectangular pads seem to be okay? (not tested much)
#    TRACE_ADJUST => 0, #(pixels) traces seemed to be okay?
#    REDUCE_TOLERANCE => .001, #(inches) allow this much variation when reducing circles and rects
#};

#Also, my CAD's Print function or the PDF print driver I used was a little off for circles, so define some additional adjustment values here:
#Values are added to X/Y coordinates; units are pixels; for example, a value of 1 at 600 dpi would be ~= .002 inch
#use constant
#{
#    CIRCLE_ADJUST_MINX => 0,
#    CIRCLE_ADJUST_MINY => -0.001 * 600, #-1, #circles were a little too high, so nudge them a little lower
#    CIRCLE_ADJUST_MAXX => +0.001 * 600, #+1, #circles were a little too far to the left, so nudge them a little to the right
#    CIRCLE_ADJUST_MAXY => 0,
#    SUBST_CIRCLE_CLIPRECT => FALSE, #generate circle and substitute for clip rects (to compensate for the way some CAD software draws circles)
#    WANT_CLIPRECT => TRUE, #FALSE, #AI doesn't need clip rect at all? should be on normally?
#    RECT_COMPLETION => FALSE, #TRUE, #fill in 4th side of rect when 3 sides found
#};

#allow .012 clearance around pads for solder mask:
#This value effectively adjusts pad sizes in the TOOL_SIZES list above (only for solder mask layers).
#use constant SOLDER_MARGIN => +.012; #units are inches

#line join/cap styles:
#use constant
#{
#    CAP_NONE => 0, #butt (none); line is exact length
#    CAP_ROUND => 1, #round cap/join; line overhangs by a semi-circle at either end
#    CAP_SQUARE => 2, #square cap/join; line overhangs by a half square on either end
#    CAP_OVERRIDE => FALSE, #cap style overrides drawing logic
#};

#number of elements in each shape type:
#use constant
#{
#    RECT_SHAPELEN => 6, #x0, y0, x1, y1, count, "rect" (start, end corners)
#    LINE_SHAPELEN => 6, #x0, y0, x1, y1, count, "line" (line seg)
#    CURVE_SHAPELEN => 10, #xstart, ystart, x0, y0, x1, y1, xend, yend, count, "curve" (bezier 2 points)
#    CIRCLE_SHAPELEN => 5, #x, y, 5, count, "circle" (center + radius)
#};
#const my %SHAPELEN =
#Readonly my %SHAPELEN =>
#our %SHAPELEN =
#(
#    rect => RECT_SHAPELEN,
#    line => LINE_SHAPELEN,
#    curve => CURVE_SHAPELEN,
#    circle => CIRCLE_SHAPELEN,
#);

#panelization:
#This will repeat the entire body the number of times indicated along the X or Y axes (files grow accordingly).
#Display elements that overhang PCB boundary can be squashed or left as-is (typically text or other silk screen markings).
#Set "overhangs" TRUE to allow overhangs, FALSE to truncate them.
#xpad and ypad allow margins to be added around outer edge of panelized PCB.
#use constant PANELIZE => {'x' => 1, 'y' => 1, 'xpad' => 0, 'ypad' => 0, 'overhangs' => TRUE}; #number of times to repeat in X and Y directions

# Set this to 1 if you need TurboCAD support.
#$turboCAD = FALSE; #is this still needed as an option?

#CIRCAD pad generation uses an appropriate aperture, then moves it (stroke) "a little" - we use this to find pads and distinguish them from PCB holes. 
#use constant PAD_STROKE => 0.3; #0.0005 * 600; #units are pixels
#convert very short traces to pads or holes:
#use constant TRACE_MINLEN => .001; #units are inches
#use constant ALWAYS_XY => TRUE; #FALSE; #force XY even if X or Y doesn't change; NOTE: needs to be TRUE for all pads to show in FlatCAM and ViewPlot
#use constant REMOVE_POLARITY => FALSE; #TRUE; #set to remove subtractive (negative) polarity; NOTE: must be FALSE for ground planes

#PDF uses "points", each point = 1/72 inch
#combined with a PDF scale factor of .12, this gives 600 dpi resolution (1/72 * .12 = 600 dpi)
#use constant INCHES_PER_POINT => 1/72; #0.0138888889; #multiply point-size by this to get inches

# The precision used when computing a bezier curve. Higher numbers are more precise but slower (and generate larger files).
#$bezierPrecision = 100;
#use constant BEZIER_PRECISION => 36; #100; #use const; reduced for faster rendering (mainly used for silk screen and thermal pads)

# Ground planes and silk screen or larger copper rectangles or circles are filled line-by-line using this resolution.
#use constant FILL_WIDTH => .01; #fill at most 0.01 inch at a time

# The max number of characters to read into memory
#use constant MAX_BYTES => 10 * M; #bumped up to 10 MB, use const

#use constant DUP_DRILL1 => TRUE; #FALSE; #kludge: ViewPlot doesn't load drill files that are too small so duplicate first tool

my $runtime = time(); #Time::HiRes::gettimeofday(); #measure my execution time


###########################################################################
#Start of main logic:
###########################################################################

#use constant INFILES => ("top copper", "bottom copper", "silk");
if ((scalar(@ARGV) < 1) || (scalar(@ARGV) > 3)) #allow up to 3 pdfs to define multiple layers in separate files
{
    my ($os, $prefix) = ($^O, "", 0); #$OSNAME
    if ($os =~ m/Win/) { $prefix = "perl"; } #bash-ify may not work on Windows (ie, without CygWin)
    DebugPrint("${\(RED)}Usage: $prefix pdf2gerb.pl <top-copper.pdf> [<bottom-copper.pdf>] [<top-silk.pdf>]${\(RESET)}", 0);
    if ($prefix ne "") { DebugPrint("${\(YELLOW)}On Windows, you may need to put \"perl\" at the start.${\(RESET)}", 0); }
    DebugPrint("${\(YELLOW)}Output files will be placed in the current working folder/directory.${\(RESET)}", 0);
    DebugPrint(sprintf("${\(RED)} %d args found (1 - 3 expected):${\(RESET)}", scalar(@ARGV)), 0);
    foreach(@ARGV) { DebugPrint("${\(CYAN)}$_${\(RESET)}", 0); }
    exit;
}

# Used by the main routine to store layer names
# first layer name will be used for output file names
our @layerTitles = ();
our %seenTypes = (); #"type" (purpose) of each layer: top/bottom and silk/copper; determined by file name and/or command line order
our $found_silk = FALSE;

#moved up here so it's only done once:
# Which layer we're on
our $currentLayer = 0;

#keep track of overall board dimensions and origin:
our %pcbLayout = ();

#summary stats:
our ($numfiles_in, $totalLines, $warnings) = (0, 0, 0, 0); #globals
our %did_file = ();

getfiles(); #read all input files
my $pdfContents = our $multiContents;
DebugPrint(sprintf("have file types: %s\n", join("\n", %seenTypes)), 2);

#debug input stream:
if (WANT_ALLINPUT) #save entire input stream (for debug ONLY)
{
    our $outputDir;
    my $filename = "all_input-$layerTitles[0].txt"; #use first layer name for output files
    $filename =~ s/-?(top|bottom|copper|silk|mask)//gi; #strip out layer type names
    open my $outstream, ">$outputDir$filename";
    print $outstream $pdfContents;
    close $outstream;
#    ++$numfiles_out;
#    $did_file{$filename} = TRUE; #don't count this one
    mywarn("input stream saved to $outputDir$filename");
}
#exit();

#try to preserve compatibility:
our $is_AI = ($pdfContents =~ m/Adobe Illustrator/gs)? TRUE: FALSE;
DebugPrint("is AI? $is_AI\n", 1);
our $rot = 0; #initialize in case not found below
#move up here to avoid warnings with AI:
our ($offsetX, $offsetY) = (0, 0);
our $scaleFactor = INCHES_PER_POINT; #0.0138888889; #use const

#pre-scan all layers to determine PCB size and origin (outline might not be on the first layer)
if (scalar(@layerTitles) > 1)
{
    our @lines = ();
    pos($pdfContents) = 0; # Reset the match position to the beginning
    while ($pdfContents =~ m/BDC(.*?)EMC/gs)
    {
        my @morelines = split /\n/, $1;
        $rot = shift(@morelines); #pull off rotation
        push(@lines, @morelines);
    }
    boundingRect(); #get pcb size and origin
}

# Break the file(s) into layers (BDC...EMC)
#my ($seen_copper, $seen_silk) = (FALSE, FALSE);
pos($pdfContents) = 0; #reset regex search position
while ($pdfContents =~ m/BDC(.*?)EMC/gs)
{
    # Break the layer into separate lines
    my ($stofs, $enofs) = ($-[0], $+[0]); #NOTE: [0] = entire pattern, [1] = first subpattern, etc.
    our @lines = split /\n/, $1;
    $rot = shift(@lines); #pull off rotation

    # Make up a layer title if there wasn't one defined in the file
#no    if (scalar(@layerTitles) <= $currentLayer) { push(@layerTitles, $layerTitles[-1]); } #layer type suffix will be added later; reuse latest file name (shouldn't happen)
    DebugPrint(sprintf("starting layer# $currentLayer/%d '$layerTitles[$currentLayer]', rot $rot, stofs $stofs, enofs $enofs\n", scalar(@layerTitles)), 1);

    #moved down to here so it can be reset for each layer
    # Used by GetAperture as well as the main routine to store aperture defn's
    our %apertures = (); #changed to hash
    # Used by GetDrillAperture
    our %drillApertures = (); #changed to hash

    # Multiply value in points by this to get value in inches
    $scaleFactor = INCHES_PER_POINT; #0.0138888889; #use const
    ($offsetX, $offsetY) = (0, 0); #note: default PDF coordinate space has origin at lower left

    our $lastAperture = "";
    our $currentDrillAperture = "";
    our $lastStrokeWeight = 1; #default to 1 point
    #remember stroke vs. fill colors separately:
#    our %visibleFillColor = ('f' => TRUE, 's' => TRUE); #0 == white (hidden), !0 == !white (visible)
    our %visibleFillColor = ('f' => MAYBE, 's' => TRUE); #0 == white (hidden), !0 == !white (visible)
    our %lineStyle = ('join' => CAP_NONE, 'cap' => CAP_ROUND); #line join/cap styles; default to previous (hard-coded) version of logic
    our $layerPolarity = TRUE; #remember last LPD/LPC emitted; initial default = visible
    our ($startPositionX, $startPositionY) = (0, 0); #remember subpath start in case path needs to be closed again later (sometimes needed)
    our ($currentX, $currentY) = (0, 0); #current location in subpath
    my $currentLine = 0; #helpful for debug
    our @drawPath = (); #drawing path
    our %holes = (); #used for overlapped hole detection
    our %masks = (); #solder masks for each pad

    our $body = ""; # list of commands generated for current layer
    our %drillBody = (); #list of holes for each drill tool size; changed to hash

    #SetAperture(1); #xform scale factor not set yet
    boundingRect(); #get/check pcb size and origin

    foreach our $line (@lines) #main loop to process PDF drawing commands
    {
        ++$currentLine; #not too useful since it's relative to embedded PDF stream, but track it anyway for debug
        if ($line =~ m/^\s*$/) { next; } #skip empty lines (silently)
        DebugPrint("linein# $currentLine: \"$line\"" . (ignore()? " IGNORED ${\(ignore())}": "") . "\n", 19);

        #process various types of PDF commands:
        if (ignore()) { next; }
        if (transforms()) { next; }
        if (drawingAttrs()) { next; }
        if (subpaths()) { next; }
        if (drawshapes()) { next; }
        #contact the authors if any others are important for your PCB
        $line =~ s/\r/\\r/g;
        $line =~ s/\n/\\n/g;
        $line =~ s/[^\x20-\x7e]/?/g; #strip control chars before displaying
        $line =~ s/%/%%/g; #esc sprintf special chars
        mywarn(sprintf("ignored: linein# $currentLine/%d $line", scalar(@lines)));
    }
    $totalLines += $currentLine;
    refillholes(); #undo unneeded holes
    DebugPrint(sprintf("body length: %.0fK, drill body len: %.0fK\n", length($body)/K, length(join("", values %drillBody))/K), 2);
    if ($body eq "") { ++$currentLayer; next; } #no output needed for empty layers

    #generate output files:
#   default layer or command line order: top copper, bottom copper, top silk, bottom silk
#    if ($currentLayer + 1 == scalar(@layerTitles)) { copper("silk"); } #assume LAST layer is silk screen
#    if ($currentLayer && ($currentLayer + 1 == scalar(@layerTitles))) { copper("silk"); } #assume LAST layer is silk screen if not also first layer
#    DebugPrint(sprintf("seen copper? $seen_copper, seen silk? $seen_silk, cur layer $currentLayer / %d '$layerTitles[$currentLayer]'\n", scalar(@layerTitles)), 10);
#    if (($layerTitles[$currentLayer] =~ m/silk/i) || ($seen_copper && !$seen_silk && ($currentLayer + 1 == scalar(@layerTitles)))) { copper("silk"); $seen_silk = TRUE; } #assume LAST layer is silk if none seen yet
#    else { copper("copper"); $seen_copper = TRUE; solder(); } #top and bottom copper
    my ($silk_or_copper, $top_or_bottom) = ("", "");
#   distinguish silk vs. copper based on name or holes:
    if ($layerTitles[$currentLayer] =~ m/-?(silk|copper)/i) { $silk_or_copper = lc $1; } #substr($1, 0, 1);
    else #if ($silk_or_copper eq "")
    {
        $silk_or_copper = (scalar(keys %drillBody) || $found_silk)? "copper": "silk"; #silk layer doesn't have holes, but if another layer is a silk layer, then treat this one as copper (in case SMD/copper only)
        $layerTitles[$currentLayer] .= "-$silk_or_copper";
    }
#   distinguish top vs. bottom based on name or order (top expected before bottom unless PCB is 1-sided):
    if ($layerTitles[$currentLayer] =~ m/-?(top|bottom)/i) { $top_or_bottom = lc $1; } #substr($1, 0, 1);
    else #if ($top_or_bottom eq "")
    {
#choose type based on previously seen layers:
 #       if (($seenTypes{"top$silk_or_copper"} || 0) < ($seenTypes{"bottom$silk_or_copper"} || 0)) { $top_or_bottom = "top"; }
 #       elsif (($seenTypes{"top$silk_or_copper"} || 0) > ($seenTypes{"bottom$silk_or_copper"} || 0)) { $top_or_bottom = "bottom"; }
#        my ($num_top, $num_bottom) = ($seenTypes{'top'} || 0, $seenTypes{'bottom'} || 0);
        my ($num_top, $num_bottom) = ($seenTypes{'top'} || 0, $seenTypes{'bottom'} || 0);
        if (($seenTypes{"top"} || 0) < ($seenTypes{"bottom"} || 0)) { $top_or_bottom = "top"; }
        elsif (($seenTypes{"top"} || 0) > ($seenTypes{"bottom"} || 0)) { $top_or_bottom = "bottom"; }
        else { $top_or_bottom = "maybe-top"; } #this is probably wrong; not sure which one to choose if #top = #bottom already, but since top pdf should come before bottom pdf on command line, assume it's the top one

        $layerTitles[$currentLayer] .= "-$top_or_bottom";
        DebugPrint("layer[$currentLayer] '$layerTitles[$currentLayer]' is top/bottom? $top_or_bottom, seen so far: #top $num_top, #bottom: $num_bottom", 5);
    }
    copper("$top_or_bottom $silk_or_copper");
    if ($silk_or_copper eq "copper") { solder($top_or_bottom); } #also need solder mask
    #only need one drill or outline file (should be the same for top + bottom); create for FIRST layer only:
    drill();
    edges();

    # Increment our layer counter
    DebugPrint("DONE with layer# $currentLayer '$layerTitles[$currentLayer]'\n", 1);
    WatchTypes($layerTitles[$currentLayer]); #CAUTION: causes double counting; should be smarter
    ++$currentLayer;
    #print $header . $body . "M02*\n";
}
$runtime -= time(); #Time::HiRes::gettimeofday();
DebugPrint(sprintf("${\(CYAN)}Files processed: $numfiles_in, written: %d, layers/streams: $currentLayer, src lines: $totalLines, warnings: $warnings${\(RESET)}\n", scalar(keys(%did_file))), 0);
#for my $filename (keys %did_file) { print STDERR $filename, "\n"; }
if ($numfiles_in) #show PCB sizes
{
    DebugPrint(sprintf("${\(CYAN)}PCB size is %5.3f x %5.3f, origin at (%5.3f, %5.3f) %s${\(RESET)}\n", inchesX($pcbLayout{'xmax'}), inchesY($pcbLayout{'ymax'}), inchesX($pcbLayout{'xmin'}), inchesY($pcbLayout{'ymin'}), METRIC? "mm": "inches"), 0);
    if (PANELIZE->{'x'} * PANELIZE->{'y'} > 1) { DebugPrint(sprintf("${\(YELLOW)}Panelized size is %5.3f x %5.3f %s${\(RESET)}\n", PANELIZE->{'x'} * inchesX($pcbLayout{'xmax'}), PANELIZE->{'y'} * inchesY($pcbLayout{'ymax'}), METRIC? "mm": "inches"), 0); }
}
DebugPrint(sprintf("${\(CYAN)}Total input stream size: %.0fK, processing time: %.2f sec${\(GREEN)}\n-end-${\(RESET)}\n", length($pdfContents)/K, -$runtime), 0); #time() - $^T; #$BASETIME


###########################################################################
#Input file parsing:
###########################################################################

#concatenate all input files:
#This is an alternative to defining multiple layers in a single PDF file.
#parameters: none (uses globals)
#return value: none (uses globals)
sub getfiles
{
    our ($numfiles_in, $multiContents, $found_silk, $outputDir, $grab_streams) = (0, "", FALSE, "", 0); #initialize globals
#    my @missing_types = qw(top bottom silk); #in preferred order
#    my %seen_types = (); #recognized layer types (purposes)
#    foreach my $filename (@ARGV) #check which file types were given
#    {
#        my $found = "";
#        if ($filename =~ m/top/i) { $found = "top"; }
#        if ($filename =~ m/bottom/i) { $found = "bottom";}
#        if ($filename =~ m/silk/i) { $found = "silk"; }
#        if ($found ne "") { splice(@missing_types, first_index { $_ eq $found }, 1); } #remove this one from missing list
#    }
#    DebugPrint("file types not found: @missing_types\n", 5);
    foreach my $pdfFilePath (@ARGV) #added outer loop
    {
        ++$numfiles_in;
#        my $purpose = ("top copper", "bottom copper", "silk")[$numfiles++]; #INFILES[$numfiles++];
        DebugPrint("${\(GREEN)}Processing input file#$numfiles_in: $pdfFilePath ...${\(RESET)}\n", 0);

        # Calculate the output dir from the input file path
        #$pdfFilePath =~ m/^(.+)\/.+$/;
        if ($outputDir eq "") #set output dir first time only, then place all output files there
        {
            my ($vol, $dir, $filename) = File::Spec->splitpath($pdfFilePath);
            #just place output files into current directory (better for separation):
            ##$dir =~ s/\.\.\\//g; #place output in subfolder even if source files are in parent
            #$outputDir = $vol . $dir;
            if ($outputDir eq "") { $outputDir = cwd() . "/"; } #default to current directory
            DebugPrint("vol $vol, dir $dir, file $filename, outdir $outputDir\n", 5);
        }

        # Open the file for reading
        #added file size warning:
        unless (-e $pdfFilePath) { --$numfiles_in; mywarn("file missing: $pdfFilePath"); next; }
        my $filesize = -s $pdfFilePath;
        my $sizewarn = ($filesize > MAX_BYTES)? sprintf("TOO BIG (> %dMB)", MAX_BYTES / 1024 / 1024): "ok";
        DebugPrint("opening file $pdfFilePath, size $filesize $sizewarn ...\n", 1);

        open my $pdfFile, "< $pdfFilePath";
        binmode $pdfFile; #PDF 1.4 flate coding is binary, not ascii

        # Read in up to MAXBYTES
        read $pdfFile, my $rawPdfContents, MAX_BYTES;
        close $pdfFile; #close file after reading
#        $rawPdfContents = decode_utf8($rawPdfContents);
#NO        $rawPdfContents = Encode::decode('iso-8859-1', $rawPdfContents); #convert to Unicode
#        my $enctype = Encode::Detect::Detector::detect($rawPdfContents);
        DebugPrint(sprintf("got %d chars from input file $pdfFilePath\n", length($rawPdfContents)), 2);

        # Fix a problem where content lines end in \r (0x0D) and are unprintable
        #@rawLines = split /(\r\n|\n\r|\n|\r)/, $rawPdfContents;
        my @rawLines = split /(\r\n|\n\r|\n|\r)/, decompress($rawPdfContents, $pdfFilePath); #PDF 1.4 requires decompress
        chomp(@rawLines);
        my $pdfContents = join("\n", @rawLines);
#TODO? preserve line#s for easier debug?
        $pdfContents =~ s/\r//gs; #remove DOS carriage returns
        $pdfContents =~ s/\n\n/\n/gs; #remove blank lines
#        $pdfContents =~ s/\n(W\*? n)/ \1/gs; #join clip command with prev line to avoid confusion with regular rects
        $pdfContents =~ s/\n(W\*? n)/ $1/gs; #join clip command with prev line to avoid confusion with regular rects
#        $pdfContents =~ s/<x:xmpmeta.*?<\/x:xmpmeta>//gs; #drop meta-data filters to prevent lots of "ignored" warnings
        $pdfContents =~ s/<\?xpacket begin.*?<\?xpacket end[^>]*>//gs; #drop meta-data filters to prevent lots of "ignored" warnings

        #some PDF editors join/split commands on a line, which makes parsing more complicated
        #try to fix it here:
        $pdfContents =~ s/(-?\d+\.?\d*)\s*\n\s*(c|-?\d+\.?\d*)\s+/$1 $2 /gs; #join c or other commands that are split across lines
        $pdfContents =~ s/(-?\d+\.?\d*\s+)(c|m)\s+(-?\d+\.?\d*)/$1$2\n$3/gs; #split c and m commands if on same line
        $pdfContents =~ s/(re|c|m|l)\s+(f|h|S|W)/$1\n$2/gs; #split re/c/m/l and f/h/S commands if on same line; also W
#        open my $outstream, ">$outputDir" . "pdfdebug.txt";
#        print $outstream $pdfContents;
#        close $outstream;
#        printf "wrote pdf contents to pdfdebug.txt\n";

        #silk screen layer seems to have a lot of independent strokes
        #string them together to cut down on silk layer size:
        my $svlen = length($pdfContents);
        for (;;) #remove redundant l/m commands; loop handles overlapping matches
        {
            my $svbuf = $pdfContents;
            $pdfContents =~ s/\n(-?\d+\s-?\d+\s)l\nS\n\1m\n/\n$1l\n/gs; #merge redundant l + m commands
            if ($pdfContents eq $svbuf) { last; } #nothing merged this time, so exit
        }
        DebugPrint(sprintf("reduced stroke chains by %d bytes (%d%%)\n", $svlen - length($pdfContents), 100 * ($svlen - length($pdfContents))/$svlen), 8);

        my $layers_in_file = 0; #count actual number of layers in file
        while ($pdfContents =~ m/BDC(.*?)EMC/gs) { ++$layers_in_file; }
        DebugPrint("#layers found in file '$pdfFilePath': $layers_in_file", 5);
        # Does BDC occur in this file?  (It will not if the file is a single layer)
#        if ($pdfContents !~ m/BDC/gs)
        if (!$layers_in_file)
        {
            # No, so -- as a hack -- let's convert "stream" -> "BDC" and "endstream" -> "EMC"
            $pdfContents =~ s/endstream/EMC/gs; #CAUTION: this might alter > 1
            $pdfContents =~ s/stream/BDC/gs;
#            ++$layers_in_file;
            pos($pdfContents) = 0; # Reset the match position to the beginning
            while ($pdfContents =~ m/BDC(.*?)EMC/gs) { ++$layers_in_file; }
            DebugPrint("no layers; modified $layers_in_file stream(s) to look like layer(s)", 5);
        }

        # Get the layer titles
#        my $numtitles = 0;
#        while ($pdfContents =~ m/\/Title\((.|\\(?=\)))+?)\)/gs)
        my $filename = basename($pdfFilePath, ".pdf"); #use file name to annotate layer name if needed
        if ($filename =~ m/-?silk/i) { $found_silk = TRUE; }
        pos($pdfContents) = 0; # Reset the match position to the beginning
        while ($pdfContents =~ m/\/Title\(((\\\)|[^)])+?)\)/gs) #allow "\)" within title; can't seem to get negative look-behind working, so just use "|" on escaped ")"
        {
#            my @title = split(/[\\\/]/, $1);
#            my ($vol, $dir, $title) = File::Spec->splitpath($1);
#            $title =~ s/^.*[\/\\]//; #drop Windows dir on Linux and vice versa (File::Spec seems to be platform-specific)
            my $title = basename($1);
            $title =~ s/^(ExpressPCB|xyz)//i; #drop hard-coded tool names
            if ($title =~ m/-?silk/i) { $found_silk = TRUE; }
            my $basename = $title;
            $basename =~ s/-?(top|bottom|copper|silk|mask)//gi; #remove layer desc, see what's left
            if ($basename !~ m/[a-z0-9]/i) { $title = "$filename$title"; $title =~ s/\s+/-/g; } #use real file name if layer just has desc
            if (($title !~ m/-?(top|bottom)/i) && ($filename =~ m/-?(top|bottom)/i)) { $title .= "-$1"; } #restore layer desc
            if (($title !~ m/-?(silk|copper)/i) && ($filename =~ m/-?(silk|copper)/i)) { $title .= "-$1"; }
            WatchTypes($title);
#            if ($projectTitle eq "") { $projectTitle = $title; } #use first title for project name
            DebugPrint(sprintf("keep layer#%d title '$title'? %d\n", scalar(@layerTitles), $layers_in_file > 0), 5);
            if ($layers_in_file > 0) { push(@layerTitles, $title); --$layers_in_file; } #don't store more titles than layers
#            ++$numtitles;
        }
#        if ($numtitles <= 1) #use file name in place of title unless file contains multiple layers
        if ($layers_in_file) #use file name in place of missing title(s)
        {
#            my ($vol, $dir, $filename) = File::Spec->splitpath($pdfFilePath);
#            $filename =~ s/\.pdf$//i; #drop file extension
#            my $filename = basename($pdfFilePath);
#no            $filename =~ s/-?(top|bottom|silk)$//i; #remove descriptive suffix from file name
#            if ($filename !~ m/(^|\W)(top|bottom|silk)$/i) #add descriptive suffix to layer/file name if not already there
#            {
#                $filename .= "-" . $missing_types[0]; #top", "-bottom", "-silk")[$numfiles - 1];
#                splice(@missing_types, 0, 1); #remove next missing type
#            }
            WatchTypes($filename);
            DebugPrint("using file name '$filename' for $layers_in_file missing titles\n", 5);
#            if (!$numtitles) { push(@layerTitles, $filename); } #add new layer name
#            else { $layerTitles[-1] = $filename; } #replace existing layer name
            while ($layers_in_file-- > 0) { push(@layerTitles, $filename); } #add new layer name; should be max 1x but use loop for safety
        }
        my $numtitles = scalar(@layerTitles);
        DebugPrint(sprintf("$numtitles = %d layers/titles kept so far: @layerTitles", scalar(@layerTitles)), 5);

        #check for page rotation:
        pos($pdfContents) = 0; # Reset the match position to the beginning
        my $rot = ($pdfContents =~ m/\/Rotate (\d+)/)? $1: 0;
        if ($rot) { DebugPrint("page is rotated $rot deg\n", 3); }
        $pdfContents =~ s/BDC/BDC$rot\n/gs; #kludge: add rotation onto layer delimiter since the layer itself doesn't have a place for that info
        DebugPrint(sprintf("now have %d chars from input file $pdfFilePath\n", length($pdfContents)), 2);

        $multiContents .= $pdfContents;
    }

    #at this point all files have been concatenated to look like multiple layers within in a single file
    $multiContents =~ s/^s$/h\nS/gs; #s = h + S; replace with equivalent PDF commands
    $multiContents =~ s/^b$/h\nB/gs; #b = h + B; replace with equivalent PDF commands
    $multiContents =~ s/^b\*$/h\nB\*/gs; #b* = h + B*; replace with equivalent PDF commands
}

#keep track of file "types" seen:
#remember top/bottom, silk/copper
sub WatchTypes
{
    our %seenTypes; #globals
    my ($name) = @_; #shift();
    my ($top_bottom, $silk_copper) = ("", "");

    $name = basename($name);
    if ($name =~ m/-?(top|bottom)/i) { $top_bottom = lc $1; } #substr($1, 0, 1);
#    if ($name =~ m/-?(silk|copper)/i) { $silk_copper = lc $1; } #substr($1, 0, 1);
#DebugPrint("watch: top/bottom $top_bottom, silk/copper $silk_copper", 0);
    if ($top_bottom ne "") { ++$seenTypes{$top_bottom} || ($seenTypes{$top_bottom} = 1); }
#    if ($silk_copper ne "") { ++$seenTypes{$silk_copper} || ($seenTypes{$silk_copper} = 1); }
#    if (($top_bottom ne "") && ($silk_copper ne "")) { ++$seenTypes{"$top_bottom$silk_copper"} || ($seenTypes{"$top_bottom$silk_copper"} = 1); }
    my ($num_top, $num_bottom) = ($seenTypes{'top'} || 0, $seenTypes{'bottom'} || 0);
    DebugPrint("watch types: '$name' is top/bottom? $top_bottom, seen so far: top $num_top, bottom $num_bottom", 5);
}

#pre-scan to find layer origin and size (bounding rect):
#This assumes that the rect or lines that define the PCB edges are outside of a transformed area,
#which seems to be the case.  (transforms seem to only apply to traces/pads).
#parameters: none (uses globals)
#return value: none (uses globals)
sub boundingRect
{
    our (@lines, $rot, $currentLayer, %layerTitles, %pcbLayout, %clipRect, $is_AI); #globals

    #For rectangular PCB, the longest horizontal and vertical lines are used to determine the PCB origin and size.
    #These could be individual line segments or a rectangle.
    #Curves and shorter lines are likely text, so they are ignored.
    my ($minX, $minY, $maxX, $maxY) = (0, 0, 0, 0); #set initial values to force first values to be captured
    my ($numlines, $srclineX, $srclineY) = (0, "?", "?"); #remember where origin/size was defined for error reporting
    my ($prevx, $prevy, $prevlineX, $prevlineY) = ("", "", "", "");
    foreach my $brline (@lines)
    {
        ++$numlines;
        if ($brline =~ m/(-?\d+\.?\d*)\s(-?\d+\.?\d*)\sm$/) #move; position is only used to define start of next line segment
        {
            ($prevx, $prevy, $prevlineX, $prevlineY) = ($1, $2, "'$brline'", "'$brline'");
            next;
        }
        if ($brline =~ m/(-?\d+\.?\d*)\s(-?\d+\.?\d*)\sl$/) #line segment
        {
            if (($2 eq $prevy) && (abs($1 - $prevx) > $maxX - $minX)) { ($minX, $maxX, $srclineX) = (min($1, $prevx), max($1, $prevx), "$prevlineX + '$brline' at line#$numlines"); }
            if (($1 eq $prevx) && (abs($2 - $prevy) > $maxY - $minY)) { ($minY, $maxY, $srclineY) = (min($2, $prevy), max($2, $prevy), "$prevlineY + '$brline' at line#$numlines"); }
            #DebugPrint("line: line $numlines, \"$minX $minY\" .. \"$maxX, $maxY\"\n", 2);
            ($prevx, $prevy, $prevlineX, $prevlineY) = ($1, $2, "'$brline'", "'$brline'");
            next;
        }
        if ($brline =~ m/(-?\d+\.?\d*)\s(-?\d+\.?\d*)\s(-?\d+\.?\d*)\s(-?\d+\.?\d*)\sre$/) #rect
        {
            if (abs($3) > $maxX - $minX) { ($minX, $maxX, $srclineX) = (min($1, $1 + $3), max($1, $1 + $3), "'$brline' at line#$numlines"); }
            if (abs($4) > $maxY - $minY) { ($minY, $maxY, $srclineY) = (min($2, $2 + $4), max($2, $2 + $4), "'$brline' at line#$numlines"); }
            #DebugPrint("rect: line $numlines, \"$minX $minY\" .. \"$maxX, $maxY\"\n", 2);
            next;
        }
    }
    if (($prevx eq "") && ($prevy eq ""))
    {
        DebugPrint("layer#$currentLayer no bounding rect", 2);
        if (scalar(%pcbLayout) || ($currentLayer + 1 != scalar(@layerTitles))) { return; } #skip this layer if there are others to choose from
    }
    if ($is_AI) { $maxX -= $minX; $maxY -= $minY; ($minX, $minY) = (0, 0); } #leave origin at (0, 0)
    DebugPrint("layer#$currentLayer '$layerTitles[$currentLayer]' bounding rect: \"$minX $minY\" .. \"$maxX, $maxY\"\n", 2);
    DebugPrint("bounding rect: used $srclineX for X\n", 4);
    DebugPrint("bounding rect: used $srclineY for Y\n", 4);

    #apply rotation to bounding box before saving it:
    #This needs to be outside the above loop since max values aren't known until the end.
    if (($rot == 90) || ($rot == 270)) { ($minX, $minY, $maxX, $maxY) = ($minY, $minX, $maxY, $maxX); }

    if (!scalar(%pcbLayout)) #use first layer to define overall pcb size
        { %pcbLayout = ('xmin' => $minX, 'ymin' => $minY, 'xmax' => $maxX, 'ymax' => $maxY, 'srcX' => $srclineX, 'srcY' => $srclineY); }
    elsif (($minX != $pcbLayout{'xmin'}) || ($minY != $pcbLayout{'ymin'})) #consistency check between layers
    {
        mywarn("layer#$currentLayer origin ($minX, $minY) doesn't match layer#0 ($pcbLayout{'xmin'}, $pcbLayout{'ymin'})");
        DebugPrint("layer#$currentLayer origin ($minX, $minY) from lines $srclineX, $srclineY\n", 3);
        DebugPrint("layer#0 origin ($pcbLayout{'xmin'}, $pcbLayout{'ymin'}) from lines $pcbLayout{'srcX'}, $pcbLayout{'srcY'}", 3);
    }
    elsif (($maxX != $pcbLayout{'xmax'}) || ($maxY != $pcbLayout{'ymax'})) #consistency check between layers
    {
        mywarn("layer#$currentLayer size ($maxX, $maxY) doesn't match layer#0 size ($pcbLayout{'xmax'}, $pcbLayout{'ymax'})");
        DebugPrint("layer#$currentLayer size ($maxX, $maxY) from lines $srclineX, $srclineY\n", 3);
        DebugPrint("layer#0 size ($pcbLayout{'xmax'}, $pcbLayout{'ymax'}) from lines $pcbLayout{'srcX'}, $pcbLayout{'srcY'}", 3);
    }

#$pcbLayout{'xmin'} = 1;
#$pcbLayout{'ymin'} = 0;
#our ($offsetX, $offsetY) = (0, 0); #note: default PDF coordinate space has origin at lower left
#our $scaleFactor = INCHES_PER_POINT; #0.0138888889; #use const
#    printf "pcb size is %5.3f x %5.3f, origin at (%5.3f, %5.3f) %s\n", inchesX($pcbLayout{'xmax'}), inchesY($pcbLayout{'ymax'}), inchesX($pcbLayout{'xmin'}), inchesY($pcbLayout{'ymin'}), METRIC? "mm": "inches";

    %clipRect = (%pcbLayout); #set initial clipping rect to entire "page" (pcb)
    unshift(@lines, "1 0 0 1 0 0 cm"); #insert a transform to recalculate origin
}

#ignore PDF commands that don't affect PCB rendering:
#parameters: none (uses globals)
#return value: true/false indicating whether the line was processed
sub ignore
{
    our ($line); #globals

#    if ($line =~ m/^\s*$/) { return TRUE; } #empty line
    #these seem to be safe to ignore:
    if ($line =~ m/\d+\si$/) { return "flatness tolerance"; } #flatness tolerance
#    if ($line =~ m/\d+\sj$/i) { return TRUE; } #line join + cap styles
    if ($line =~ m/\sgs$/i) { return "graphics state dictionary"; } #graphics state dictionary
    if ($line =~ m/Q$/i) { return "graphics state save/restore"; } #save/restore graphics state
    
    return FALSE; #check for other commands
}

#handle transforms:
#NOTE: junk at start of line is ignored
#parameters: none (uses globals)
#return value: true/false indicating whether the line was processed
sub transforms
{
    our ($line, $offsetX, $offsetY, $scaleFactor, %pcbLayout, $is_AI); #globals

    if ($line =~ m/1 0 0 1 (-?\d+\.?\d*)\s(-?\d+\.?\d*)\scm$/) #transformation matrix (translation)
    {
        # Lines ending in cm define a transformation matrix...
        # 1 0 0 1 X Y means offset all values by X and Y.

        our $numxform;
        ++$numxform;
        ($offsetX, $offsetY) = (tenths($1) - $pcbLayout{'xmin'}, tenths($2) - $pcbLayout{'ymin'}); #set origin to lower left corner
#        if ($is_AI) { ($offsetX, $offsetY) = (0, 0); } #leave origin at (0, 0) for AI
        #print "offset:" . $1 . " " . $2 . "\n";
        DebugPrint(sprintf("xform# $numxform offset ($1, $2) => adj ofs ($offsetX, $offsetY), pcb layout (%5.5f, %5.5f) .. (%5.5f, %5.5f)\n", inchesX($pcbLayout{'xmin'}), inchesY($pcbLayout{'ymin'}), inchesX($pcbLayout{'xmax'}), inchesY($pcbLayout{'ymax'})), 10);
        return TRUE;
    }

    if ($line =~ m/(-?\d+\.?\d*)\s0 0 (-?\d+\.?\d*)\s0 0 cm$/) #transformation matrix (scaling)
    {
        #size + coords were incorrect, so this is needed
        #other useful info at: http://www.asppdf.com/manual_04.html
        # [sx 0 0 sy 0 0] = scaled; this is the one I am seeing

        if ($1 != $2) { mywarn("non-proportional scaling transform ($1 vs. $2) not implemented"); }
        $scaleFactor *= $1; # a value of .12 * 1/72 gives 1/600, which gives 600 dpi resolution
        DebugPrint(sprintf("xform scale: ($1, $2) => factor %5.5f, pcb layout (%5.5f, %5.5f) .. (%5.5f, %5.5f)\n", $scaleFactor, inchesX($pcbLayout{'xmin'}), inchesY($pcbLayout{'ymin'}), inchesX($pcbLayout{'xmax'}), inchesY($pcbLayout{'ymax'})), 10);
        return TRUE;
    }

    return FALSE; #xform not found, check for other commands
}


#handle drawing attrs:
#NOTE: junk at start of line is ignored
#parameters: none (uses globals)
#return value: true/false indicating whether the line was processed
sub drawingAttrs
{
    our ($line, %visibleFillColor, %lineStyle, $lastStrokeWeight); #globals

    if ($line =~ m/(\d+\.?\d*)\s(g)$/i) #Gray Space
    {
        my $which = ($2 eq "g")? 'f': 's'; #stroke vs. fill (upper vs lower case command); i.e. G or g - never used in circad it seems?
        #One number followed by g define the current fill color in Gray Space
        #We want to ignore anything drawn in white
        $visibleFillColor{$which} = ($1 == 1)? FALSE: TRUE; # This changes color to white, which makes things invisible
        #print "fill color:" . $1 . " " . $ 1 . " " . $1 . "\n";
        DebugPrint("$which color rgb $1 $1 $1 => vis-$which $visibleFillColor{$which}\n", 5);
        return TRUE;
    }

    if ($line =~ m/(\d+\.?\d*)\s(j)$/i) #line join + cap styles ( 0 = butt, 1 = round, 2 = square )
    {
        my $which = ($2 eq "j")? 'join': 'cap'; #join vs. cap style (upper vs. lower case command)
# Used to generate square or round pads only; TODO: use for fill style also
        $lineStyle{$which} = $1; #($1 == 0)? "b": ($1 == 1)? "r": ($1 == 2)? "s": ; #remember join/cap style
        DebugPrint(sprintf("line $which-style $1 => %s\n", ($1 == CAP_ROUND)? "round": ($1 == CAP_SQUARE)? "square": ($1 == CAP_NONE)? "none": "UNKNOWN"), 5);
        return TRUE;
    }

    if ($line =~ m/(\d+\.?\d*)\s(\d+\.?\d*)\s(\d+\.?\d*)\s(rg)$/i) #RGB color; distinguish stroke vs. fill
    {
        my $which = ($4 eq "rg")? 'f': 's'; #stroke vs. fill (upper vs. lower case command)
        # Three numbers followed by rg define the current fill color in RGB
        # We want to ignore anything drawn in white
        $visibleFillColor{$which} = (($1 == 1) && ($2 == 1) && ($3 == 1))? FALSE: TRUE; # This changes color to white, which makes things invisible
        #print "fill color:" . $1 . " " . $2 . " " . $3 . "\n";
        DebugPrint("$which color rgb $1 $2 $3 => vis-$which $visibleFillColor{$which}\n", 5);
        return TRUE;
    }
        
    if ($line =~ m/(\d+\.?\d*)\s(\d+\.?\d*)\s(\d+\.?\d*)\s(\d+\.?\d*)\s(k)$/i) #CYMK color; distinguish stroke vs. fill
    {
        my $which = ($5 eq "k")? 'f': 's'; #stroke vs. fill (upper vs. lower case command)
        # Four numbers followed by k define the current fill color in CMYK
        # We want to ignore anything drawn in white
        $visibleFillColor{$which} = (($1 == 0) && ($2 == 0) && ($3 == 0) && ($4 == 0))? FALSE: TRUE; # This changes color to white, which makes things invisible
        #print "fill color:" . $1 . " " . $2 . " " . $3 . "\n";
        DebugPrint("$which color cmyk $1 $2 $3 => vis-$which $visibleFillColor{$which}\n", 10);
        return TRUE;
    }
        
    if ($line =~ m/(\d+\.?\d*)\sw/) #stroke weight (in points)
    {
        # Number followed by w is a stroke weight
        #print "weight:" . $1 . "\n";
        DebugPrint(sprintf("weight: %5.5f \"$1\"\n", inches($1)), 10);
        $lastStrokeWeight = $1;
        #defer aperture selection until needed:
        return TRUE;
    }

    if ($line =~ m/(\d+\.?\d*)\sM/) #miter limit
    {
        DebugPrint(sprintf("miter limit: %5.5f \"$1\" IGNORED\n", inches($1)), 10);
        return TRUE;
    }

    return FALSE; #drawing attr not found, check for other commands
}

#drawing subpaths:
#This will save line segments and arcs, or other elements in the drawing path until the next fill or stroke command.
#NOTE: junk at start of line is ignored for MOST commands.
#parameters: none (uses globals)
#return value: true/false indicating whether the line was processed
sub subpaths
{
    our ($line, @drawPath, $startPositionX, $startPositionY, $startXY, $currentX, $currentY, $curXY, %visibleFillColor, $lastStrokeWeight); #globals

    if ($line =~ m/(-?\d+\.?\d*)\s(-?\d+\.?\d*)\s(-?\d+\.?\d*)\s(-?\d+\.?\d*)\sre$/) #rect
    {
        # Lines ending in re define a rectangle, often followed
        # by W n to define the clipping rect

        my ($startx, $starty) = rotate($1, $2);
        my ($endx, $endy) = rotate(tenths($1 + $3), tenths($2 + $4)); #convert w, h to max x, y
        push(@drawPath, (min($startx, $endx), min($starty, $endy), max($startx, $endx), max($starty, $endy), 1, "rect")); #add rect to draw path; NOTE: rotation might have reversed coords, so check min/max again
        DebugPrint(sprintf("rect: (%5.5f, %5.5f) .. (%5.5f, %5.5f) \"$1 $2 +$3 +$4\", vis-f $visibleFillColor{'f'}, weight $lastStrokeWeight\n", inchesX($drawPath[-6]), inchesY($drawPath[-5]), inchesX($drawPath[-4]), inchesY($drawPath[-3])), 10);

        ($startPositionX, $startPositionY, $startXY) = (0, 0, "0 0"); #rect closes current subpath
        ($currentX, $currentY, $curXY) = (0, 0, "0 0"); #rect closes current subpath
        if (!WANT_CLIPRECT || $is_AI) { popshape(); } #AI doesn't want clip rect to show 
        return TRUE;
    }

    if ($line =~ m/(-?\d+\.?\d*)\s(-?\d+\.?\d*)\sm$/) #start new subpath
    {
        # Lines ending in m mean move to a position, which can be used
        # to close a path later on

        ($startPositionX, $startPositionY, $startXY) = (rotate(tenths($1), tenths($2)), "$1 $2"); #keep start position of drawing subpath
        ($currentX, $currentY, $curXY) = ($startPositionX, $startPositionY, "$1 $2"); #keep last position in drawing subpath
        DebugPrint(sprintf("move \"$curXY\" & ($currentX, $currentY) = (%5.5f, %5.5f)", inchesX($currentX), inchesY($currentY)), 5);
        return TRUE;
    }
        
    if ($line =~ m/(-?\d+\.?\d*)\s(-?\d+\.?\d*)\sl$/) #line segment
    {
        # Lines ending in l mean draw a straight line to this position

        my ($endx, $endy) = rotate($1, $2);
        push(@drawPath, ($currentX, $currentY, $endx, $endy, numshapes("line") + 1, "line"));
        DebugPrint(sprintf("line: from (%5.5f, %5.5f) \"$curXY\" to (%5.5f, %5.5f) \"$1 $2\" \"$line\", vis-s $visibleFillColor{'s'}, weight %5.5f \"$lastStrokeWeight\"\n", inchesX($drawPath[-6]), inchesY($drawPath[-5]), inchesX($drawPath[-4]), inchesY($drawPath[-3]), inches($lastStrokeWeight)), 5);

        ($currentX, $currentY, $curXY) = ($endx, $endy, "$1 $2"); #remember last position in drawing subpath
        return TRUE;
    }

    if ($line =~ m/^h$/) #close subpath
    {
        # h means draw a straight line back to the first point

#not sure we want to do this:
#        if (($currentX == $startPositionX) && ($currentY == $startPositionY)) #skip this subpath (prevents circle reduction, which doesn't allow it to be a round pad or drill hole)
#        {
#            DebugPrint(sprintf("close: ignoring benign (%5.5f, %5.5f) \"$curXY\" back to self, vis-s $visibleFillColor{'s'}, weight $lastStrokeWeight\n", inchesX($currentX), inchesY($currentY)), 10);
#            return TRUE;
#        }
        push(@drawPath, ($currentX, $currentY, $startPositionX, $startPositionY, numshapes("line") + 1, "line"));
        DebugPrint(sprintf("close: from (%5.5f, %5.5f) \"$curXY\" back to (%5.5f, %5.5f) \"$drawPath[-4] $drawPath[-3]\", vis-s $visibleFillColor{'s'}, weight $lastStrokeWeight\n", inchesX($drawPath[-6]), inchesY($drawPath[-5]), inchesX($drawPath[-4]), inchesY($drawPath[-3])), 10);

        ($startPositionX, $startPositionY, $startXY) = (0, 0, "0 0"); #close current subpath
        ($currentX, $currentY, $curXY) = (0, 0, "0 0"); #close current subpath
        return TRUE;
    }

    if ($line =~ m/(-?\d+\.?\d*)\s(-?\d+\.?\d*)\s(-?\d+\.?\d*)\s(-?\d+\.?\d*)\s(-?\d+\.?\d*)\s(-?\d+\.?\d*)\sc$/) #cubic bezier (3 points)
    {
        # Lines ending in c mean draw a bezier path to this point (x1 y1 x2 y2 x3 y3)
        # x1 y1 x2 y2 x3 y3
        # The curve extends from the current point to the point (x3, y3), 
        # using (x1, y1) and (x2, y2) as the Bezier control points.
        # The new current point is (x3, y3).

        my ($endx, $endy) = rotate($5, $6);
        push(@drawPath, ($currentX, $currentY, rotate($1, $2), rotate($3, $4), $endx, $endy, numshapes("curve") + 1, "curve"));
        DebugPrint(sprintf("curve-c: from (%5.5f, %5.5f) \"$curXY\" thru (%5.5f, %5.5f) \"$1 $2\" and (%5.5f, %5.5f) \"$3 $4\" to (%5.5f, %5.5f) \"$5 $6\", vis-s $visibleFillColor{'s'}, weight %5.5f \"$lastStrokeWeight\"\n", inchesX($drawPath[-10]), inchesY($drawPath[-9]), inchesX($drawPath[-8]), inchesY($drawPath[-7]), inchesX($drawPath[-6]), inchesY($drawPath[-5]), inchesX($drawPath[-4]), inchesY($drawPath[-3]), inches($lastStrokeWeight)), 5);
# our ($offsetX, $offsetY);
#        DebugPrint(sprintf("cur ofs ($offsetX, $offsetY) => (%5.5f, %5.5f)", inchesX(0), inchesY(0)), 5);

        ($currentX, $currentY, $curXY) = ($endx, $endy, "$5 $6"); #remember last position in subpath
        return TRUE;
    }

    if ($line =~ m/(-?\d+\.?\d*)\s(-?\d+\.?\d*)\s(-?\d+\.?\d*)\s(-?\d+\.?\d*)\sv$/) #cubic bezier (2 points)
    {
        # Lines ending in v mean draw a bezier curve (x2 y2 x3 y3)
        # x2 y2 x3 y3.
        # The curve extends from the current point to the point (x3, y3),
        # using the current point and (x2, y2) as the Bezier control points.
        # The new current point is (x3, y3).

        my ($endx, $endy) = rotate($3, $4);
#our $scaleFactor;
#my $xadj = 288 + 3; #8.5 / $scaleFactor / 2;
#my $yadj = -36 -2;
#DebugPrint(sprintf("adjust curve-1 by %5.5f, %5.5f", $xadj, $yadj), 5);
#        push(@drawPath, ($currentX - $xadj, $currentY - $yadj, $currentX - $xadj, $currentY - $yadj, rotate($1 - $xadj, $2 - $yadj), $endx - $xadj, $endy - $yadj, numshapes("curve") + 1, "curve"));
        push(@drawPath, (rotate($currentX, $currentY), rotate($currentX, $currentY), rotate($1, $2), rotate($endx, $endy), numshapes("curve") + 1, "curve"));
        DebugPrint(sprintf("curve-v: from (%5.5f, %5.5f) \"$curXY\" thru (%5.5f, %5.5f) \"$1 $2\" to (%5.5f, %5.5f) \"$3 $4\", vis-s $visibleFillColor{'s'}, weight $lastStrokeWeight\n", inchesX($drawPath[-10]), inchesY($drawPath[-9]), inchesX($drawPath[-6]), inchesY($drawPath[-5]), inchesX($drawPath[-4]), inchesY($drawPath[-3])), 5);
# our ($offsetX, $offsetY);
#        DebugPrint(sprintf("cur ofs ($offsetX, $offsetY) => (%5.5f, %5.5f)", inchesX(0), inchesY(0)), 5);

        ($currentX, $currentY, $curXY) = ($endx, $endy, "$3 $4"); #remember last position in subpath
        return TRUE;
    }
        
    if ($line =~ m/(-?\d+\.?\d*)\s(-?\d+\.?\d*)\s(-?\d+\.?\d*)\s(-?\d+\.?\d*)\sy$/) #cubic bezier (2 points)
    {
        # Lines ending in y mean draw a bezier curve (x1 y1 x3 y3)
        # x1 y1 x3 y3.
        # The curve extends from the current point to the point (x3, y3), 
        # using (x1, y1) and (x3, y3) as the Bezier control points.
        # The new current point is (x3, y3).

        my ($endx, $endy) = rotate($3, $4);
#our $scaleFactor;
#my $xadj = 288 + 3; #8.5 / $scaleFactor / 2;
#my $yadj = -36 -2;
#DebugPrint(sprintf("adjust curve-1 by %5.5f, %5.5f", $xadj, $yadj), 5);
#        push(@drawPath, ($currentX - $xadj, $currentY - $yadj, rotate($1 - $xadj, $2 - $yadj), $endx - $xadj, $endy - $yadj, $endx - $xadj, $endy - $yadj, numshapes("curve") + 1, "curve"));
        push(@drawPath, (rotate($currentX, $currentY), rotate($1, $2), rotate($endx, $endy), rotate($endx, $endy), numshapes("curve") + 1, "curve"));
        DebugPrint(sprintf("curve-y: from (%5.5f, %5.5f) \"$curXY\" thru (%5.5f, %5.5f) \"$1 $2\" to (%5.5f, %5.5f) \"$3 $4\", vis-s $visibleFillColor{'s'}, weight $lastStrokeWeight\n", inchesX($drawPath[-10]), inchesY($drawPath[-9]), inchesX($drawPath[-8]), inchesY($drawPath[-7]), inchesX($drawPath[-4]), inchesY($drawPath[-3])), 5);

        ($currentX, $currentY, $curXY) = ($endx, $endy, "$3 $4"); #keep last position in subpath
        return TRUE;
    }

    return FALSE; #subpath not found, check for other commands
}

#apply stroke or fill to subpaths:
#This is the main function to draw pads, holes, traces, and ground planes.
#parameters: none (uses globals)
#return value: true/false indicating whether the line was processed
sub drawshapes
{
    our ($line, @drawPath, %clipRect, %lineStyle, $lastStrokeWeight, %visibleFillColor); #globals

    if ($line =~ m/W\*? n$/) #clip rect
    {
        # W n makes the prev re command set the clipping rect
        #NOTE: this ignores winding + even-odd rules
        #ignore clip rect for now; not used anywhere
        #reduceRect(); #check if last 3 or 4 line segments in drawing path make a rect
        #if ($drawPath[-1] eq "rect") #intersect clipping rect with drawing path to get new clip rect
        #{
        #    ($clipRect{'xmin'}, $clipRect{'ymin'}) = (max($clipRect{'xmin'}, $drawPath[-6]), max($clipRect{'ymin'}, $drawPath[-5]));
        #    ($clipRect{'xmax'}, $clipRect{'ymax'}) = (min($clipRect{'xmax'}, $drawPath[-4]), min($clipRect{'ymax'}, $drawPath[-3]));
        #    DebugPrint(sprintf("new clip rect: (%5.5f, %5.5f) .. (%5.5f, %5.5f)\n", inchesX($clipRect{'xmin'}), inchesY($clipRect{'ymin'}), inchesX($clipRect{'xmax'}), inchesY($clipRect{'ymax'})), 8);
        #}
        #else { mywarn("clip region $drawPath[-1] not implemented"); }
        #popshape();

        #most CAD software does not seem to need clip rects, so they can be safely ignored
        #however, this behavior can be overridden using the SUBST_CIRCLE_CLIPRECT option, as a work-around for CAD software that uses clip rects along with other, unrecognized drawing commands
        if (!SUBST_CIRCLE_CLIPRECT) { return TRUE; }
        reduceRect(); #check if last 3 or 4 line segments in drawing path make a rect
        if (scalar(@drawPath) < 2) { mywarn(sprintf("not a rect: %d", scalar(@drawPath))); }
        elsif ($drawPath[-1] eq "rect") #intersect clipping rect with drawing path to get new clip rect
        {
            my ($minX, $minY, $maxX, $maxY) = ($drawPath[-6], $drawPath[-5], $drawPath[-4], $drawPath[-3]);
            DebugPrint(sprintf("clip rect: (%5.5f, %5.5f) .. (%5.5f, %5.5f) replaced with circle; TODO: WHY?\n", inchesX($minX), inchesY($minY), inchesX($maxX), inchesY($maxY)), 8);
            popshape();
            push(@drawPath, (($minX + $maxX)/2, ($minY + $maxY)/2, $maxX - $minX, 1, "circle")); #replace clip rect with circle; WHY?
        }
        else { mywarn("clip region $drawPath[-2] $drawPath[-1] not implemented"); }
        return TRUE;
    }
        
    if ($line =~ m/^n$/) #noop (discard path)
    {
        DebugPrint("noop: shape $drawPath[-1]\n", 5);
        popshape();
        return TRUE;
    }

    if ($line =~ m/^B$/) #fill-and-stroke
    {
        DebugPrint("fill-and-stroke: ignore fill and just stroke\n", 10);
        $line = "S"; #kludge: just use fill logic
#        return TRUE;
    }

    if ($line =~ m/^S$/) #stroke: draw current path
    {
        # S means stroke what we just drew - only supported for circles
        # as a workaround for TurboCAD, which can't fill circles (!)
        #update: this now handles lines and curves

#        reduceRect(); #check if last 4 line segments in drawing path make a rect
#        reduceCircle(); #check if last 4 curves in drawing path make a circle
#        convertPad(); #kludge: convert very short traces to pads/holes
#        SetPolarity('s');
#        SetAperture('t', $lastStrokeWeight + TRACE_ADJUST);
#        DebugPrint(sprintf("path waiting for stroke: %d, stroke weight: $lastStrokeWeight, polarity $visibleFillColor{'s'}\n", scalar(@drawPath)), 5);
        while (scalar(@drawPath)) #draw all subpaths that are waiting
        {
            reduceRect(); #check if last 4 line segments in drawing path make a rect
            reduceCircle(); #check if last 4 curves in drawing path make a circle
            if (convertPad()) { fill(); } #kludge: convert very short traces to pads
            else #trace
            {
                SetPolarity('s');
#                our $body;
#                $body .= "G04 here1\n";
                SetAperture_shape('t', topshape(), $lastStrokeWeight + TRACE_ADJUST);
#                if ($lineStyle{'cap'} == CAP_ROUND) { SetAperture('t', topshape(), $lastStrokeWeight + TRACE_ADJUST); }
#                elsif ($lineStyle{'cap'} == CAP_SQUARE) { SetAperture('t', topshape(), $lastStrokeWeight + TRACE_ADJUST, $lastStrokeWeight + TRACE_ADJUST); }
#                else { mywarn("which aperture?"); }
                outline();
            }
            if (popshape()) { next; }
            DebugPrint("failed to outline subpath\n", 5);
            @drawPath = ();
        }
        return TRUE;
    }

    if ($line =~ m/^f\*?$/) #fill; small rect or circles are treated as pads; small white filled circles are treated as holes
    {
        #NOTE: this ignores PDF winding + even-odd rules
        #NOTE: "*" is for odd-even fill path rule; rule is ignored
#        reduceRect(); #check if last 4 line segments in drawing path make a rect
#        reduceCircle(); #check if last 4 curves in drawing path make a circle
#        DebugPrint(sprintf("path waiting for fill: %d, polarity $visibleFillColor{'f'}\n", scalar(@drawPath)), 5);
        while (scalar(@drawPath)) #fill all subpaths that are waiting
        {
            reduceRect(); #check if last 4 line segments in drawing path make a rect
            reduceCircle(); #check if last 4 curves in drawing path make a circle
            fill();
            if (popshape()) { next; }
            DebugPrint("failed to fill subpath\n", 5);
            @drawPath = ();
        }
        return TRUE;
    }

    return FALSE; #shape not found, check for other commands
}

#draw outline for next shape in path:
#This function generates traces and text.
#Also used around line-filled areas to give a smoother edge.
#parameters: none (uses globals)
#return value: none (uses globals)
sub outline
{
    our (@drawPath, %visibleFillColor, $lastStrokeWeight, $lastAperture, $body); #globals
    my ($ofs) = scalar(@_)? @_: (0); #offset toward center

    if ($drawPath[-1] eq "rect") #draw rect edges
    {
        if ($ofs) #nudge toward center of rect (gives more accurate outline on filled rect)
        {
            $drawPath[-6] += $ofs; #minX is known to be < centerX
            $drawPath[-5] += $ofs; #minY is known to be < centerY
            $drawPath[-4] -= $ofs; #maxX is known to be > centerX
            $drawPath[-3] -= $ofs; #maxY is known to be > centerY
        }
        DebugPrint(sprintf("stroke rect: (%5.5f, %5.5f) .. (%5.5f, %5.5f), vis-s $visibleFillColor{'s'}, weight $lastStrokeWeight, aper $lastAperture\n", inchesX($drawPath[-6]), inchesY($drawPath[-5]), inchesX($drawPath[-4]), inchesY($drawPath[-3])), 8);
        $body .= sprintf("X%sY%sD02*\n", inchesX($drawPath[-6], FALSE), inchesY($drawPath[-5], FALSE)); #move to lower left corner
        $body .= sprintf("Y%sD01*\n", inchesY($drawPath[-3], FALSE)); #draw to upper left corner
        $body .= sprintf("X%sD01*\n", inchesX($drawPath[-4], FALSE)); #draw to upper right corner
        $body .= sprintf("Y%sD01*\n", inchesY($drawPath[-5], FALSE)); #draw to lower right corner
        $body .= sprintf("X%sD01*\n", inchesX($drawPath[-6], FALSE)); #draw to lower left corner again
        return TRUE;
    }

    if ($drawPath[-1] eq "line") #line segment or polygon
    {
        if ($ofs) #nudge edges "inward" (gives more accurate outline because it compensates for line width)
        {
            #for each edge, determine which direction is toward "inside" of polygon:
            my %inside = ();
            for (my $j = -LINE_SHAPELEN * $drawPath[-2]; $j < 0; $j += LINE_SHAPELEN)
            {
                my ($midX, $midY, $deltaX, $deltaY) = (($drawPath[$j + 0] + $drawPath[$j + 2])/2, ($drawPath[$j + 1] + $drawPath[$j + 3])/2, $drawPath[$j + 2] - $drawPath[$j + 0], $drawPath[$j + 3] - $drawPath[$j + 1]);
#                my $slope = $deltaX? $deltaY/$deltaX: MAXINT;
                #first pick a test point near the center of but not on this edge:
                my $edgelen = sqrt($deltaX **2 + $deltaY **2);
                if ($edgelen < 0.00001) { DebugPrint(sprintf("no edge delta? (%5.5f, %5.5f) - (%5.5f, %5.5f)", $drawPath[$j + 0], $drawPath[$j + 2], $drawPath[$j + 1], $drawPath[$j + 3]), 5); next; }
                my ($testX, $testY) = ($midX - $deltaY * $ofs / $edgelen, $midY + $deltaX * $ofs / $edgelen); #move a short distance perpendicular to center of polygon's edge
                #then check whether test point is inside or outside the polygon:
                #The code below is based on the point-in-polygon algorithm described at http://alienryderflex.com/polygon/
                $inside{$j} = +$ofs; #assume outside for now; <0 => inside, >0 => outside
                for (my $i = -LINE_SHAPELEN * $drawPath[-2]; $i < 0; $i += LINE_SHAPELEN)
                {
                    if ((min($drawPath[$i + 1], $drawPath[$i + 3]) >= $testY) || (max($drawPath[$i + 1], $drawPath[$i + 3]) < $testY)) { next; } #polygon side doesn't cross test point
#?                    if (($drawPath[$i + 0] > $testX) && ($drawPath[$i + 2] > $testX)) { next; } #only need to check edges to one side of test point
                    my $x = $drawPath[$i] + ($testY - $drawPath[$i + 1]) / ($drawPath[$i + 3] - $drawPath[$i + 1]) * ($drawPath[$i + 2] - $drawPath[$i + 0]); #intersection of test line with edge
                    DebugPrint(sprintf("polygon edge %d intersects at X= %5.5f, this is %s test point X\n", -$i/LINE_SHAPELEN, inchesX($x), ($x < $testX)? "<": ($x > $testX)? ">": "="), 5);
                    if ($testX <= $x) { next; } #test point lies to the left of polygon edge
                    $inside{$j} = -$inside{$j}; #track inside/outside parity
                }
                DebugPrint(sprintf("polygon edge %d check: (%5.5f, %5.5f) .. (%5.5f, %5.5f), test point %s%s (%5.5f, %5.5f) inside? %d\n", -$j/LINE_SHAPELEN, inchesX($drawPath[$j + 0]), inchesY($drawPath[$j + 1]), inchesX($drawPath[$j + 2]), inchesY($drawPath[$j + 3]), ($testX < $midX)? "-": ($testX > $midX)? "+": "=", ($testY < $midY)? "-": ($testY > $midY)? "+": "=", inchesX($testX), inchesY($testY), $inside{$j}), 5);
            }

            #now move the polygon edge toward the "inside" of the polygon:
            #NOTE: "inward" may mean toward or away from the center of the polygon, depending on orientation of polygon edges
            for (my $i = -LINE_SHAPELEN * $drawPath[-2]; $i < 0; $i += LINE_SHAPELEN)
            {
                my ($svx0, $svy0, $svx1, $svy1) = ($drawPath[$i + 0], $drawPath[$i + 1], $drawPath[$i + 2], $drawPath[$i + 3]);
                my ($deltaX, $deltaY) = ($drawPath[$i + 2] - $drawPath[$i + 0], $drawPath[$i + 3] - $drawPath[$i + 1]);
                my $edgelen = sqrt($deltaX **2 + $deltaY **2);
                if ($edgelen < 0.00001) { next; }
                #move edge toward or away from test point, based on whether it was inside or outside the polygon:
                ($drawPath[$i + 0], $drawPath[$i + 1]) = ($drawPath[$i + 0] + $inside{$i} * $deltaY / $edgelen, $drawPath[$i + 1] - $inside{$i} * $deltaX / $edgelen);
                ($drawPath[$i + 2], $drawPath[$i + 3]) = ($drawPath[$i + 2] + $inside{$i} * $deltaY / $edgelen, $drawPath[$i + 3] - $inside{$i} * $deltaX / $edgelen);
                DebugPrint(sprintf("polygon edge %d nudge: (%5.5f, %5.5f) .. (%5.5f, %5.5f), test pt inside poly? %d, new edge: (%5.5f, %5.5f) .. (%5.5f, %5.5f)\n", -$i/LINE_SHAPELEN, inchesX($svx0), inchesY($svy0), inchesX($svx1), inchesY($svy1), $inside{$i}, inchesX($drawPath[$i + 0]), inchesY($drawPath[$i + 1]), inchesX($drawPath[$i + 2]), inchesY($drawPath[$i + 3])), 5);
            }

            #lastly, lengthen or shorten the polygon edges so the corners touch again (so polygon can be filled):
            #This is done by finding the intersection of the pair of equations through each corner.
            #There's probably a more efficient way, but this works and it isn't executed frequently.
            #TODO: use line join style (round/square/butt)
            for (my ($i, $previ) = (-LINE_SHAPELEN * $drawPath[-2], -LINE_SHAPELEN); $i < 0; $previ = $i, $i += LINE_SHAPELEN)
            {
                #given 2 points on a line, the line's equation is: y = (Y2 - Y1)/(X2 - X1)(x - X1) + Y1, or just x = X1 if the line is vertical
                my ($deltaX, $deltaY) = ($drawPath[$i + 2] - $drawPath[$i + 0], $drawPath[$i + 3] - $drawPath[$i + 1]);
                my ($prevdeltaX, $prevdeltaY) = ($drawPath[$previ + 2] - $drawPath[$previ + 0], $drawPath[$previ + 3] - $drawPath[$previ + 1]);
                my ($cornerX, $cornerY) = ($drawPath[$i + 0], $drawPath[$i + 1]);
                if (!$deltaX) #special case: current edge is a vertical line
                {
                    if (!$prevdeltaX) { mywarn("2 adjacent polygon edges are vertical?"); } #shouldn't happen (2 adjacent edges should not be parallel)
                    else { $cornerY = $prevdeltaY/$prevdeltaX * ($cornerX - $drawPath[$previ + 0]) + $drawPath[$previ + 1]; }
#                    DebugPrint(sprintf("corner-vert-now = (%5.5f, %5.5f), prev delta (%5.5f, %5.5f)\n", inchesX($cornerX), inchesY($cornerY), inchesX($prevdeltaX), inchesY($prevdeltaY)), 60);
                }
                elsif (!$prevdeltaX) #special case: previous edge was a vertical line
                {
                    $cornerX = $drawPath[$previ + 2];
                    $cornerY = $deltaY/$deltaX * ($cornerX - $drawPath[$i + 0]) + $drawPath[$i + 1];
#                    DebugPrint(sprintf("corner-vert-prev = (%5.5f, %5.5f), cur delta (%5.5f, %5.5f)\n", inchesX($cornerX), inchesY($cornerY), inchesX($deltaX), inchesY($deltaY)), 60);
                }
                elsif (abs($deltaY/$deltaX - $prevdeltaY/$prevdeltaX) < .0001) { mywarn(sprintf("2 adjacent polygon edges are parallel: edge[%d] (%5.5f, %5.5f) - (%5.5f, %5.5f) and edge[%d] (%5.5f, %5.5f) - (%5.5f, %5.5f)", -$i/LINE_SHAPELEN, inchesX($drawPath[$i + 0]), inchesY($drawPath[$i + 1]), inchesX($drawPath[$i + 2]), inchesY($drawPath[$i + 3]), -$previ/LINE_SHAPELEN, inchesX($drawPath[$previ + 0]), inchesY($drawPath[$previ + 1]), inchesX($drawPath[$previ + 2]), inchesY($drawPath[$previ + 3]))); } #shouldn't happen (2 adjacent edges should not be parallel)
                else #neither edge is vertical, solve for x then y
                {
                    if ($deltaY/$deltaX == $prevdeltaY/$prevdeltaX) { mywarn("2 adjacent polygon edges are parallel?"); } #shouldn't happen (2 adjacent edges should not be parallel)
                    $cornerX = $deltaY/$deltaX * $cornerX - $prevdeltaY/$prevdeltaX * $drawPath[$previ + 2] + $drawPath[$previ + 3] - $cornerY;
                    $cornerX /= $deltaY/$deltaX - $prevdeltaY/$prevdeltaX;
                    $cornerY = $deltaY/$deltaX * ($cornerX - $drawPath[$i + 2]) + $drawPath[$i + 3];
#                    DebugPrint(sprintf("corner-non-vert = (%5.5f, %5.5f), cur delta (%5.5f, %5.5f), prev delta (%5.5f, %5.5f)\n", inchesX($cornerX), inchesY($cornerY), inchesX($deltaX), inchesY($deltaY), inchesX($prevdeltaX), inchesY($prevdeltaY)), 60);
#                    if (($cornerX > 10000) || ($cornerY > 10000)) { DebugPrint("WHOOPS\n"); }
                }
                DebugPrint(sprintf("polygon corner %d: moved from (%5.5f, %5.5f) to (%5.5f, %5.5f)\n", -$i/LINE_SHAPELEN, inchesX($drawPath[$i + 0]), inchesY($drawPath[$i + 1]), inchesX($cornerX), inchesY($cornerY)), 5);
                ($drawPath[$i + 0], $drawPath[$i + 1]) = ($cornerX, $cornerY);
                ($drawPath[$previ + 2], $drawPath[$previ + 3]) = ($cornerX, $cornerY); #update both copies of the corner
            }
        }
        #draw polygon edges:
        for (my ($i, $first) = (-LINE_SHAPELEN * $drawPath[-2], TRUE); $i < 0; $i += LINE_SHAPELEN, $first = FALSE)
        {
            if ($first) { $body .= sprintf("X%sY%sD02*\n", inchesX($drawPath[$i + 0], FALSE), inchesY($drawPath[$i + 1], FALSE)); } #move to first corner
            $body .= sprintf("X%sY%sD01*\n", inchesX($drawPath[$i + 2], FALSE), inchesY($drawPath[$i + 3], FALSE)); #line to next corner
            DebugPrint(sprintf("poly outline %d: (%5.5f, %5.5f) .. (%5.5f, %5.5f)\n", -$i/LINE_SHAPELEN, inchesX($drawPath[$i + 0]), inchesY($drawPath[$i + 1]), inchesX($drawPath[$i + 2]), inchesY($drawPath[$i + 3])), 8);
        }
        if ($drawPath[-2] > 1) { DebugPrint("polygon: drew outline using $drawPath[-2] line segs, aper $lastAperture\n", 5); }
        return TRUE;
    }

    if ($drawPath[-1] eq "curve") #arc (bezier curve); arc or part of a circle, not a full circle
    {
        if ($ofs) { mywarn("arc offset $ofs not implemented"); } #probably a bug
        #NOTE: this handles circles on silk scren layer (4 bezier curves are used, one for each quadrant)

        DebugPrint(sprintf("stroke curve: (%5.5f, %5.5f) thru (%5.5f, %5.5f) and (%5.5f, %5.5f) to (%5.5f, %5.5f), vis-s $visibleFillColor{'s'}, weight $lastStrokeWeight, aper $lastAperture\n", inchesX($drawPath[-10]), inchesY($drawPath[-9]), inchesX($drawPath[-8]), inchesY($drawPath[-7]), inchesX($drawPath[-6]), inchesY($drawPath[-5]), inchesX($drawPath[-4]), inchesY($drawPath[-3])), 8);
        my ($x0, $y0, $x1, $y1, $x2, $y2, $x3, $y3) = ($drawPath[-10], $drawPath[-9], $drawPath[-8], $drawPath[-7], $drawPath[-6], $drawPath[-5], $drawPath[-4], $drawPath[-3]);
        #compute Bezier curve points as before:
        # R(t) = (1Ðt)^3 * P0 + 3t(1Ðt)^2 * P1 + 3t^2(1Ðt) P2 + t^3 P3  where t -> 0 .. 1.0
#TODO: start or end below loop with $ofs; not sure how to decide which case
        for (my $t = 0; $t <= 1.0; $t += 1/BEZIER_PRECISION)
        {
            # Compute the new X and Y locations
            my ($t0, $t1, $t2, $t3) = ((1 - $t) **3, 3 * $t * (1 - $t) **2, 3 * $t **2 * (1 - $t), $t **3);
            my $x = $t0 * $x0 + $t1 * $x1 + $t2 * $x2 + $t3 * $x3;
            my $y = $t0 * $y0 + $t1 * $y1 + $t2 * $y2 + $t3 * $y3;
            # Draw this segment of the curve
            $body .= sprintf("X%sY%sD0%d*\n", inchesX($x, FALSE), inchesY($y, FALSE), $t? 1: 2); #move to first, draw to others
        }
        return TRUE;
    }

    if ($drawPath[-1] eq "circle") #full circle (4 arcs were reduced)
    {
        if ($ofs) { $drawPath[-3] -= 2 * $ofs; } #nudge toward center (gives more accurate outline)
        my ($centerX, $centerY, $diameter, $radius) = ($drawPath[-5], $drawPath[-4], $drawPath[-3], $drawPath[-3]/2);
        my $angle_delta = 360 / (inches(PI * $diameter) / FILL_WIDTH); #draw circle using line segments of .01 inch
        DebugPrint(sprintf("stroke circle: center (%4.4f, %4.4f), diameter %5.5f, circumference %5.5f, angle delta %5.5f, aper $lastAperture\n", inchesX($centerX), inchesY($centerY), inches($diameter), inches(PI * $diameter), $angle_delta), 5);
        for (my $i = 0; $i <= 360; $i += $angle_delta) #go a little extra (past 360 degrees) to make sure circle is completed
        {
            my $angle = PI * $i/180; #cumulative angle (radians)
            my ($x, $y) = ($centerX + $radius * sin($angle), $centerY + $radius * cos($angle));
            $body .= sprintf("X%sY%sD0%d*\n", inchesX($x, FALSE), inchesY($y, FALSE), $i? 1: 2); #move to start point, draw line segments to remaining points
        }
        return TRUE;
    }

    mywarn("outline shape $drawPath[-1] not implemented");
    return FALSE;
}

#fill next shape in path:
#This function generates pads, holes and other filled areas.  Also generates masks.
#Circles and rectangles can be pads, circles can be holes, polygons are typically graphics or ground plane.
#parameters: none (uses globals)
#return value: none (uses globals)
sub fill
{
    our (@drawPath, %visibleFillColor, %lineStyle, $lastStrokeWeight, $lastAperture, $body, $currentDrillAperture, %masks, %holes, %drillBody, $bez_warn); #globals

    if ($drawPath[-1] eq "rect") #fill a rect; NOTE: might be square/rect pad or ground plane; can't be a hole (holes are round)
    {
        SetPolarity('f');
#        our $body;
#        $body .= "G04 here2\n";
        my ($minX, $minY, $maxX, $maxY) = (min($drawPath[-6], $drawPath[-4]), min($drawPath[-5], $drawPath[-3]), max($drawPath[-6], $drawPath[-4]), max($drawPath[-5], $drawPath[-3])); #use min/max in case rect is rendered backwards
#        my ($minX, $minY, $maxX, $maxY) = ($drawPath[-6], $drawPath[-5], $drawPath[-4], $drawPath[-3]); #use min/max in case rect is rendered backwards
        my ($w, $h) = ($maxX - $minX, $maxY - $minY);
        my $is_square = (inches(abs($w - $h)) < TRACE_MINLEN); #($w == $h); #NOTE: need to use rounding to compensate for arithmetic errors
        DebugPrint(sprintf("fill rect: size %5.5f x %5.5f, area (%4.4f, %4.4f) .. (%4.4f %4.4f), vis-f $visibleFillColor{'f'}, weight %5.5f \"$lastStrokeWeight\", use aperture? %d (max %5.5f, flash treshold %5.5f), w %s h, is square? %s\n", inches($w), inches($h), inchesX($minX), inchesY($minY), inchesX($maxX), inchesY($maxY), inches($lastStrokeWeight), inches(min($w, $h)) <= MAX_APERTURE, MAX_APERTURE, TRACE_MINLEN, ($w < $h)? "<": ($w > $h)? ">": "=", $is_square), 5);

        #use this code to always use rectangular apertures of any size:
        #SetAperture('x', $w + SQRPAD_ADJUST, $h + SQRPAD_ADJUST); #select smaller dimension as aperture size
        #$body .= sprintf("X%sY%sD03*\n", inchesX(($minX + $maxX)/2, FALSE), inchesY(($minY + $maxY)/2, FALSE)); #move and flash
        #DebugPrint(sprintf("flash rect: use aperture $lastAperture %5.5f \"$w\" at (%5.5f, %5.5f), has mask? %d\n", inches($w), inchesX(($minX + $maxX)/2), inchesY(($minY + $maxY)/2), $visibleFillColor{'f'}), 5);
        #return TRUE;

        if (!MAX_APERTURE || (inches(min($w, $h)) <= MAX_APERTURE)) #small enough to use aperture
        {
            my $aper_size = min($w, $h) + ($is_square? SQRPAD_ADJUST: RECTPAD_ADJUST); #select smaller dimension as aperture size
            SetAperture('p', topshape(), $aper_size, $aper_size); #, $aper_size); #or, use 'x' for exact size here?
            my $masklen = length($body);
#NOTE: very short traces don't seem to show up in ViewPlot and FlatCAM, so flash aperture instead
            if (($w < $h) && !$is_square) #drag aperture vertically
            {
                $body .= sprintf("X%sY%sD02*\n", inchesX(($minX + $maxX)/2, FALSE), inchesY($minY + $w/2, FALSE)); #move to starting point
                $body .= sprintf("Y%sD01*\n", inchesY($maxY - $w/2, FALSE)); #draw to other end (X does not change)
                DebugPrint(sprintf("draw vrect: use aperture $lastAperture %5.5f \"$w\" with line from (%5.5f, %5.5f) to (\", %5.5f), has mask? %d\n", inches($w), inchesX(($minX + $maxX)/2), inchesY($minY + $w/2), inchesY($maxY - $w/2), $visibleFillColor{'f'}), 5);
            }
            elsif (($w > $h) && !$is_square) #drag aperture horizontally
            {
                $body .= sprintf("X%sY%sD02*\n", inchesX($minX + $h/2, FALSE), inchesY(($minY + $maxY)/2, FALSE)); #move to starting point
                $body .= sprintf("X%sD01*\n", inchesX($maxX - $h/2, FALSE)); #draw to other end (Y does not change)
                DebugPrint(sprintf("draw hrect: use aperture $lastAperture %5.5f \"$h\" with line from (%5.5f, %5.5f) to (%5.5f, \"), has mask? %d\n", inches($h), inchesX($minX + $h/2), inchesY(($minY + $maxY)/2), inchesX($maxX - $h/2), $visibleFillColor{'f'}), 5);
            }
            else #flash aperture to draw a square
            {
                $body .= sprintf("X%sY%sD03*\n", inchesX(($minX + $maxX)/2, FALSE), inchesY(($minY + $maxY)/2, FALSE)); #move and flash
                DebugPrint(sprintf("flash rect: use aperture $lastAperture %5.5f \"$w\" at (%5.5f, %5.5f), has mask? %d\n", inches($w), inchesX(($minX + $maxX)/2), inchesY(($minY + $maxY)/2), $visibleFillColor{'f'}), 5);
            }
#            if ($visibleFillColor{'f'}) #generate mask for this pad
            if ($visibleFillColor{'f'} != FALSE) #generate mask for this pad
            {
                if ((inchesX($minX) < 0) || (inchesY($minY) < 0)) { mywarn(sprintf("bad mask %5.5f, %5.5f", inchesX($minX), inchesY($minY))); } #bug; should never happen
                my $mask = sprintf("%d,%d\n", $aper_size + SOLDER_MARGIN, $aper_size + SOLDER_MARGIN); #add .012" to pad size for mask
                $mask .= substr($body, $masklen); #pad commands are re-used to draw mask
                my $padxy = sprintf("X%sY%s", inchesX($minX, FALSE), inchesY($minY, FALSE)); #mask keyed off lower left corner
                $masks{$padxy} = $mask;
            }
            return TRUE;
        }

        #fill rect by drawing a bunch of parallel lines:
        SetAperture('f', topshape(), points(FILL_WIDTH), points(FILL_WIDTH)); #draw outline to preserve overall shape + size; use square aperture
        #draw border first so it's smooth:
        #line width is .01 centered on border, so move it a half-width toward center of rect to preserve overall rect size correctly
        outline(points(FILL_WIDTH)/2);
        ($minX, $minY, $maxX, $maxY) = ($drawPath[-6], $drawPath[-5], $drawPath[-4], $drawPath[-3]); #refresh values after offset nudge
        my $inc = points(FILL_WIDTH - .001); #overlap each line by .001 to prevent gaps in filled area due to rounding errors
        if ($w >= $h) #fill with horizontal lines
        {
            $minY += $inc;
            for (my ($y, $numinc) = ($minY, 0); $y < $maxY; $y += $inc, ++$numinc)
            {
                #zig-zag fill to reduce head movement: (might be unnecessary with digital photoplotters)
                $body .= sprintf("X%sY%sD02*\n", inchesX(even($numinc)? $maxX: $minX, FALSE), inchesY($y, FALSE)); #move
                $body .= sprintf("X%sD01*\n", inchesX(even($numinc)? $minX: $maxX, FALSE)); #draw; Y didn't change, don't need to send it again
                DebugPrint(sprintf("zzhfill: #inc $numinc, even? %d, from (%5.5f, %5.5f) to (%5.5f, \"), inc %5.5f \"$inc\", next %5.5f \"%d\", limit %5.5f \"$maxY\"\n", even($numinc), inchesX(even($numinc)? $maxX: $minX), inchesY($y), inchesX(even($numinc)? $minX: $maxX), inches($inc), inchesY($y + $inc), $y + $inc, inchesY($maxY)), 15);
            }
        }
        else #fill with vertical lines
        {
            $minX += $inc;
            for (my ($x, $numinc) = ($minX, 0); $x < $maxX; $x += $inc, ++$numinc)
            {
                #zig-zag fill to reduce head movement: (might be unnecessary with digital photoplotters)
                $body .= sprintf("X%sY%sD02*\n", inchesX($x, FALSE), inchesY(even($numinc)? $maxY: $minY, FALSE)); #move
                $body .= sprintf("Y%sD01*\n", inchesY(even($numinc)? $minY: $maxY, FALSE)); #draw; X didn't change, don't need to send it again
                DebugPrint(sprintf("zzyfill: #inc $numinc, even? %d, from (%5.5f, %5.5f) to (\", %5.5f), inc %5.5f \"$inc\", next %5.5f \"%d\", limit %5.5f \"$maxX\"\n", even($numinc), inchesX($x), inchesY(even($numinc)? $maxY: $minY), inchesY(even($numinc)? $minY: $maxY), inches($inc), inchesX($x + $inc), $x + $inc, inchesX($maxX)), 15);
            }
        }
        return TRUE;
    }

    if ($drawPath[-1] eq "circle") #fill a circle; NOTE: might be round pad or hole
    {
        my ($centerX, $centerY, $diameter, $drillxy) = ($drawPath[-5], $drawPath[-4], $drawPath[-3], sprintf("X%sY%s", inchesX($drawPath[-5], FALSE), inchesY($drawPath[-4], FALSE)));
#        my $ishole = ((!MAX_DRILL || (inches($diameter + HOLE_ADJUST) <= MAX_DRILL)) && !$visibleFillColor{'f'}); #small and not visible; this is probably a drill hole
        my $ishole = ((!MAX_DRILL || (inches($diameter + HOLE_ADJUST) <= MAX_DRILL)) && ($visibleFillColor{'f'} != TRUE)); #small and not visible; this is probably a drill hole
        $diameter += $ishole? HOLE_ADJUST: RNDPAD_ADJUST; #compensate for rendering arithmetic errors
        DebugPrint(sprintf("fill circle: center (%4.4f, %4.4f) \"$drawPath[-5] $drawPath[-4]\", diameter %5.5f (adjusted to %5.5f), weight $lastStrokeWeight, vis-f $visibleFillColor{'f'}, use aperture? %d, to drill? %d, prev drill? %d\n", inchesX($centerX), inchesY($centerY), inches($drawPath[-3]), inches($diameter), inches($diameter) <= MAX_APERTURE, $ishole, exists($holes{$drillxy})), 5);
        if (exists($holes{$drillxy})) #undo any previous (larger) drill hole at this location before drilling new (smaller) hole
        {
            my ($svcount, $svtool) = (scalar(keys %holes), $holes{$drillxy});
            if ($drillBody{$svtool} !~ m/\Q$drillxy\E\n/s) { mywarn("'$drillxy' NOT FOUND IN $svtool LIST: '$drillBody{$svtool}'"); } #probably a bug
            $drillBody{$svtool} =~ s/\Q$drillxy\E\n//s; #remove from earlier list of locations to be drilled
            delete($holes{$drillxy});
            DebugPrint(sprintf("removed $drillxy from $svtool drill list, hole count was $svcount, is now %d, hole still defined? %d, still in drill list? %d\n", scalar(keys %holes), exists($holes{$drillxy}), ($drillBody{$svtool} =~ m/^\Q$drillxy\E$/)? 1: 0), 5);
        }
        if ($ishole) #add to drill list
        {
            SetDrillAperture($diameter);
            $drillBody{$currentDrillAperture} .= "$drillxy\n"; #list of hole locations for this drill size
            $holes{$drillxy} = $currentDrillAperture; #add to potential undo list, in case a smaller hole comes later at same location
            $body .= "G04 drill $currentDrillAperture $drillxy*\n"; #remember start of fill commands for this hole
            $diameter += RNDPAD_ADJUST - HOLE_ADJUST; #re-adjust for pad; pad will be used later to refill this hole if another comes later at this same location
        }

        #NOTE: holes also flow through the code below.
        #We don't *really* know yet if a white circle is a hole or just clearance around a round pad in a ground plane,
        #so *both* are generated here, and then one of them is discarded later.
        if (!MAX_APERTURE || (inches($diameter) <= MAX_APERTURE)) #pad (visible or invisible); small enough to use aperture
        {
            SetPolarity('f');
            SetAperture('p', topshape(), $diameter); # - $lastStrokeWeight/2); #stroke is centered on circumference
            my $masklen = length($body);
            $body .= sprintf("X%sY%sD03*\n", inchesX($centerX, FALSE), inchesY($centerY, FALSE)); #move + flash
#            if ($visibleFillColor{'f'}) #generate mask for this pad
            if ($visibleFillColor{'f'} != FALSE) #generate mask for this pad
            {
                if (exists($masks{$drillxy})) #use largest size at this location
                {
                    my $prev_mask = $masks{$drillxy};
                    if (($prev_mask =~ m/^(\d+)\n/s) && ($1 > $diameter))
                    {
                        DebugPrint(sprintf("using prior larger pad ($prev_mask) at this location: %5.5f => %5.5f", $diameter, $1), 5);
                        $diameter = max($diameter, $1);
                    }
                }
                my $mask = sprintf("%d\n", $diameter + SOLDER_MARGIN); #add .012" to pad size
                $mask .= substr($body, $masklen); #pad commands are re-used to draw mask
                $masks{$drillxy} = $mask; #keyed off center
            }
        }
        else #fill larger circles by drawing a bunch of parallel lines
        {
            #draw border first so it's smooth(er):
            SetPolarity('f');
            SetAperture('f', topshape(), points(FILL_WIDTH)); #outline to preserve overall shape + size
            #line width is .01 centered on border, so move it a half-width toward center of circle to preserve overall circle size correctly
            outline(points(FILL_WIDTH)/2);
            my $radius = $drawPath[-3]/2; #refresh values after offset nudge
            #now fill with parallel lines:
            #Fill with radial lines requires (PI * diameter / 2 / fill-width) lines; fill with horizontal lines requires (diameter / fill-width) lines.
            #Since PI / 2 > 1, it's more efficient to use horizontal lines rather than radial lines to fill the circular area.
            my $inc = points(FILL_WIDTH - .001); #overlap each line by .001 to prevent gaps due to rounding errors
            my ($minY, $maxY) = ($centerY - $radius + $inc, $centerY + $radius);
            for (my ($y, $numinc) = ($minY, 0); $y < $maxY; $y += $inc, ++$numinc)
            {
                my $xofs = sqrt($radius **2 - ($centerY - $y) **2);
                #zig-zag fill to reduce head movement: (might be unnecessary with digital photoplotters)
                $body .= sprintf("X%sY%sD02*\n", inchesX(even($numinc)? $centerX - $xofs: $centerX + $xofs, FALSE), inchesY($y, FALSE)); #move
                $body .= sprintf("X%sD01*\n", inchesX(even($numinc)? $centerX + $xofs: $centerX - $xofs, FALSE)); #draw; Y didn't change, don't need to send it again
                DebugPrint(sprintf("zzhfill: #inc $numinc, even? %d, xofs %5.5f, from (%5.5f, %5.5f) to (%5.5f, \"), inc %5.5f \"$inc\", next %5.5f \"%d\", limit %5.5f \"$maxY\"\n", even($numinc), $xofs, inchesX(even($numinc)? $centerX - $xofs: $centerX + $xofs), inchesY($y), inchesX(even($numinc)? $centerX + $xofs: $centerX - $xofs), inches($inc), inchesY($y + $inc), $y + $inc, inchesY($maxY)), 15);
            }
        }
        if (exists($holes{$drillxy})) { $body .= "G04 /drill $holes{$drillxy} $drillxy*\n"; } #remember end of fill commands for this hole
        return TRUE;
    }

    if (($drawPath[-1] eq "line") && ($drawPath[-2] >= 2)) #fill a polygon (used mainly for ground plane areas with irregular edges)
    {
        if (($drawPath[-4] != $drawPath[-LINE_SHAPELEN * $drawPath[-2]]) || ($drawPath[-3] != $drawPath[-LINE_SHAPELEN * $drawPath[-2] + 1])) #not closed
        {
            #this seems to happen only near the start of the PDF, for PCB border or maybe also for filled ground plane areas
            my ($startX, $startY, $endX, $endY, $numsides) = ($drawPath[-4], $drawPath[-3], $drawPath[-LINE_SHAPELEN * $drawPath[-2]], $drawPath[-LINE_SHAPELEN * $drawPath[-2] + 1], $drawPath[-2]);
            DebugPrint(sprintf("unclosed poly: $drawPath[-2] sides, adding (%5.5f, %5.5f) .. (%5.5f, %5.5f)\n", inchesX($drawPath[-4]), inchesY($drawPath[-3]), inchesX($drawPath[-LINE_SHAPELEN * $drawPath[-2]]), inchesY($drawPath[-LINE_SHAPELEN * $drawPath[-2] + 1])), 5);
            push(@drawPath, ($drawPath[-4], $drawPath[-3], $drawPath[-LINE_SHAPELEN * $drawPath[-2]], $drawPath[-LINE_SHAPELEN * $drawPath[-2] + 1], $drawPath[-2] + 1, "line"));
        }
        #draw border first so it's smooth:
        SetPolarity('f');
        SetAperture_shape('f', topshape(), points(FILL_WIDTH)); #draw outline to preserve overall shape + size
#        if ($lineStyle{'cap'} == CAP_ROUND) { SetAperture('f', topshape(), points(FILL_WIDTH)); } #draw outline to preserve overall shape + size; use square aperture
#        else { SetAperture('f', topshape(), points(FILL_WIDTH), points(FILL_WIDTH)); } #draw outline to preserve overall shape + size; use square aperture
        #line width is .01 centered on border, so move it a half-width toward center of circle to preserve overall circle size correctly
        outline(points(FILL_WIDTH)/2);

        polyfill(\@drawPath, -2, LINE_SHAPELEN);
        popshape($drawPath[-2] - 1); #kludge: caller will pop last line segment
        return TRUE;
    }

    if ($drawPath[-1] eq "line") #fill a single line; what does this mean?  must be some graphics
    {
        SetPolarity('f');
        SetAperture_shape('f', topshape(), points(FILL_WIDTH)); #, points(FILL_WIDTH)); #draw outline to preserve overall shape + size; use square aperture
#        #line width is .01 centered on border, so move it a half-width toward center of circle to preserve overall circle size correctly
#        outline(points(FILL_WIDTH)/2);
        outline(0); #no need to adjust center of a stand-alone line seg?
#NOTE: caller will pop shape since it is only 1 line segment
        return TRUE;
    }

    if ($drawPath[-1] eq "curve") #used for silk screen graphics, not traces or holes
    {
#first draw border so it's smooth(er):
        SetPolarity('f');
        SetAperture('f', topshape(), points(FILL_WIDTH)); #outline to preserve overall shape + size
#line width is .01 centered on border, so move it a half-width toward center of circle to preserve overall circle size correctly
        outline(points(FILL_WIDTH)/2);
#then fill bezier curve using a polygon:
        if (TRUE) { return TRUE; }
        if (!$bez_warn) { DebugPrint("install Math::Bezier from cpan and uncomment \"use\" near start\n", 1); $bez_warn = 1; }
# x3[-10] y5[-9] x2[-8] y5[-7] x1[-6] y4[-5] x1[-4] y3[-3] c
        my $bez = Math::Bezier->new($drawPath[-10], $drawPath[-9], $drawPath[-8], $drawPath[-7], $drawPath[-6], $drawPath[-5], $drawPath[-4], $drawPath[-3]); #4 (x, y) points
#        my ($x, $y) = $bezier->point(0.5); #(x,y) points along curve, range 0..1
        my @curve = $bez->curve(BEZIER_PRECISION); #list of (x,y) points along curve
#        $diameter += RNDPAD_ADJUST; #compensate for rendering arithmetic errors
#        DebugPrint(sprintf("fill circle: center (%4.4f, %4.4f) \"$drawPath[-5] $drawPath[-4]\", diameter %5.5f (adjusted to %5.5f), weight $lastStrokeWeight, vis-f $visibleFillColor{'f'}, use aperture? %d, to drill? %d, prev drill? %d\n", inchesX($centerX), inchesY($centerY), inches($drawPath[-3]), inches($diameter), inches($diameter) <= MAX_APERTURE, $ishole, exists($holes{$drillxy})), 5);
        polyfill(\@curve, 0, 2);
        return TRUE;
    }

    mywarn("fill shape '$drawPath[-1]' $drawPath[-2] not implemented");
    return FALSE;
}


#fill a polygon using parallel lines
sub polyfill
{
    our $body; #globals
    my @myPath = @{ shift() }; #get first param as array
    my $stofs = shift(); #-2
    my $stride = shift(); #6
#    my ($myPath, $stofs, $stride) = @_; #coords, start ofs, stride

    if (scalar(@myPath) < 2) { return FALSE; } #avoid subscript error (short-circuit IF polyfill
    #determine bounding rect (used as limits for fill):
    my ($minX, $minY, $maxX, $maxY) = (0, 0, 0, 0); #initialize in case polygon is incomplete
    for (my ($i, $first) = (-$stride * $myPath[$stofs], TRUE); $i < 0; $i += $stride, $first = FALSE)
    {
        $minX = min($first? $myPath[$i + 0]: $minX, $myPath[$i + 2]);
        $minY = min($first? $myPath[$i + 1]: $minY, $myPath[$i + 3]);
        $maxX = max($first? $myPath[$i + 0]: $maxX, $myPath[$i + 2]);
        $maxY = max($first? $myPath[$i + 1]: $maxY, $myPath[$i + 3]);
    }
    DebugPrint(sprintf("polygon: bounding rect (%5.5f, %5.5f) .. (%5.5f, %5.5f) \"$minX $minY $maxX $maxY\", $myPath[-2] line segs\n", inchesX($minX), inchesY($minY), inchesX($maxX), inchesY($maxY)), 5);

    #now fill polygon by drawing parallel lines:
    #Based on 2007 code from Darel Rex Finley at http://alienryderflex.com/polygon_fill/
    #NOTE: algorithm doesn't care if polygon corners were clockwise or counterclockwise, so we can ignore PDF even/odd rules.
    my $inc = points(FILL_WIDTH - .001); #overlap each line by .001 to prevent gaps in filled area due to rounding errors
    $minY += $inc;
    for (my $y = $minY; $y < $maxY; $y += $inc)
    {
        #build a list of intersection points of current fill line with polygon sides:
        my @Xcrossing = ();
        for (my $i = -$stride * $myPath[$stofs]; $i < 0; $i += $stride)
        {
            if ((min($myPath[$i + 1], $myPath[$i + 3]) >= $y) || (max($myPath[$i + 1], $myPath[$i + 3]) < $y)) { next; } #polygon side doesn't cross current fill line
            my $x = $myPath[$i] + ($y - $myPath[$i + 1]) / ($myPath[$i + 3] - $myPath[$i + 1]) * ($myPath[$i + 2] - $myPath[$i + 0]); #intersection of test line with edge
            push(@Xcrossing, $x);
        }
        if (!scalar(@Xcrossing)) { next; }
        @Xcrossing = sort @Xcrossing;
        DebugPrint(sprintf("fill poly: at y %5.5f found %d crossings: %s\n", inchesY($y), scalar(@Xcrossing), join(", ", @Xcrossing)), 8);
        #fill between each pair of points:
        for (my $i = 0; $i + 1 < scalar(@Xcrossing); $i += 2)
        {
            $body .= sprintf("X%sY%sD02*\n", inchesX($Xcrossing[$i], FALSE), inchesY($y, FALSE)); #move
            $body .= sprintf("X%sD01*\n", inchesX($Xcrossing[$i + 1], FALSE)); #draw; Y didn't change, don't need to send it again
            DebugPrint(sprintf("polyhfill: from (%5.5f, %5.5f) to (%5.5f, \"), inc %5.5f \"$inc\", next %5.5f \"%d\", limit %5.5f \"$maxY\"\n", inchesX($Xcrossing[$i]), inchesY($y), inchesX($Xcrossing[$i + 1]), inches($inc), inchesY($y + $inc), $y + $inc, inchesY($maxY)), 15);
        }
    }
}


#reduce last 3 or 4 line segments in drawing path to make a rect:
#This only seems to be used for overall PCB outline.
#NOTE: rectangle must be orthogonal to X + Y axes
#parameters: none (uses globals)
#return value: true/false telling if a rect was found
sub reduceRect
{
    our @drawPath; #globals
    my $num_sides = RECT_COMPLETION? 3: 4;

    if (scalar(@drawPath) < 2) { return FALSE; } #avoid subscript error (short-circuit IF doesn't work); is this a bug?
    if ((scalar(@drawPath) < 2) || ($drawPath[-1] ne "line") || ($drawPath[-2] < $num_sides)) { DebugPrint(sprintf("not $num_sides lines: non-rect: %d, %s, %d\n", scalar(@drawPath), $drawPath[-1], $drawPath[-2]), 5); return FALSE; } #subpath doesn't contain 3-4 line segments
#    if ((scalar(@drawPath) < 2) || ($drawPath[-1] ne "line") || ($drawPath[-2] < 3)) { return FALSE; } #subpath doesn't contain 4 line segments

#just check for 3 or 4 line segments chained together, and assume it's rectangular:
# x4[-24] y4[-23] x1[-22] y1[-21] - this one might be missing
# x1[-18] y1[-17] x2[-16] y2[-15]
# x2[-12] y2[-11] x3[-10] y3[-9]
# x3[-6] y3[-5] x4[-4] y4[-3]
    my ($x1, $y1, $x4, $y4) = ($drawPath[-2] < 4)? (-18, -17, -4, -3): (-22, -21, -24, -23); #indexes to check for 4th line seg
    #don't need to check end-points (was already checked before updating line count at [-2]):
    #check if line segments are parallel to X or Y axes:

#compare corners, not lines:
#    if ((inches(abs($drawPath[$x4] - $drawPath[$x1])) > REDUCE_TOLERANCE) && (inches(abs($drawPath[$y4] - $drawPath[$y1])) > REDUCE_TOLERANCE)) { DebugPrint(sprintf("!rect: [$x4] %d != [$x1] %d by %5.5f && [$y4] %d != [$y1] %d by %5.5f\n", $drawPath[$x4], $drawPath[$x1], inches(abs($drawPath[$x4] - $drawPath[$x1])), $drawPath[$y4], $drawPath[$y1], inches(abs($drawPath[$y4] - $drawPath[$y1]))), 5); return FALSE; }
#    if ((inches(abs($drawPath[-18] - $drawPath[-16])) > REDUCE_TOLERANCE) && (inches(abs($drawPath[-17] - $drawPath[-15])) > REDUCE_TOLERANCE)) { DebugPrint(sprintf("!rect: [-18] %d != [-16] %d by %5.5f && [-17] %d != [-15] %d by %5.5f\n", $drawPath[-18], $drawPath[-16], inches(abs($drawPath[-18] - $drawPath[-16])), $drawPath[-17], $drawPath[-15], inches(abs($drawPath[-17] - $drawPath[-15]))), 5); return FALSE; }
#    if ((inches(abs($drawPath[-12] - $drawPath[-10])) > REDUCE_TOLERANCE) && (inches(abs($drawPath[-11] - $drawPath[-9])) > REDUCE_TOLERANCE)) { DebugPrint(sprintf("!rect: [-12] %d != [-10] %d by %5.5f && [-11] %d != [-9] %d by %5.5f\n", $drawPath[-12], $drawPath[-10], inches(abs($drawPath[-12] - $drawPath[-10])), $drawPath[-11], $drawPath[-9], inches(abs($drawPath[-11] - $drawPath[-9]))), 5); return FALSE; }
#    if ((inches(abs($drawPath[-6] - $drawPath[-4])) > REDUCE_TOLERANCE) && (inches(abs($drawPath[-5] - $drawPath[-3])) > REDUCE_TOLERANCE)) { DebugPrint(sprintf("!rect: [-16] %d != [-4] %d by %5.5f && [-5] %d != [-3] %d by %5.5f\n", $drawPath[-6], $drawPath[-4], inches(abs($drawPath[-6] - $drawPath[-4])), $drawPath[-5], $drawPath[-3], inches(abs($drawPath[-5] - $drawPath[-3]))), 5); return FALSE; }
    if ((inches(abs($drawPath[$x4] - $drawPath[-4])) > REDUCE_TOLERANCE) || (inches(abs($drawPath[$y4] - $drawPath[-3])) > REDUCE_TOLERANCE)) { DebugPrint(sprintf("!rect: [$x4] %d != [$x1] %d by %5.5f && [$y4] %d != [$y1] %d by %5.5f\n", $drawPath[$x4], $drawPath[-4], inches(abs($drawPath[$x4] - $drawPath[$x1])), $drawPath[$y4], $drawPath[-3], inches(abs($drawPath[$y4] - $drawPath[-3]))), 5); return FALSE; }
    if ((inches(abs($drawPath[-18] - $drawPath[$x1])) > REDUCE_TOLERANCE) || (inches(abs($drawPath[-17] - $drawPath[$y1])) > REDUCE_TOLERANCE)) { DebugPrint(sprintf("!rect: [-18] %d != [$x1] %d by %5.5f && [-17] %d != [$y1] %d by %5.5f\n", $drawPath[-18], $drawPath[$x1], inches(abs($drawPath[-18] - $drawPath[$x1])), $drawPath[-17], $drawPath[$y1], inches(abs($drawPath[-17] - $drawPath[$y1]))), 5); return FALSE; }
    if ((inches(abs($drawPath[-12] - $drawPath[-16])) > REDUCE_TOLERANCE) || (inches(abs($drawPath[-11] - $drawPath[-15])) > REDUCE_TOLERANCE)) { DebugPrint(sprintf("!rect: [-12] %d != [-16] %d by %5.5f && [-11] %d != [-15] %d by %5.5f\n", $drawPath[-12], $drawPath[-16], inches(abs($drawPath[-12] - $drawPath[-16])), $drawPath[-11], $drawPath[-15], inches(abs($drawPath[-11] - $drawPath[-15]))), 5); return FALSE; }
    if ((inches(abs($drawPath[-6] - $drawPath[-10])) > REDUCE_TOLERANCE) || (inches(abs($drawPath[-5] - $drawPath[-9])) > REDUCE_TOLERANCE)) { DebugPrint(sprintf("!rect: [-6] %d != [-10] %d by %5.5f && [-5] %d != [-9] %d by %5.5f\n", $drawPath[-6], $drawPath[-10], inches(abs($drawPath[-6] - $drawPath[-10])), $drawPath[-5], $drawPath[-9], inches(abs($drawPath[-5] - $drawPath[-9]))), 5); return FALSE; }
#    if ((inches(abs($drawPath[$x4] - $drawPath[$x1])) > REDUCE_TOLERANCE) && (inches(abs($drawPath[$y4] - $drawPath[$y1])) > REDUCE_TOLERANCE)) { return FALSE; }
#    if ((inches(abs($drawPath[-18] - $drawPath[-16])) > REDUCE_TOLERANCE) && (inches(abs($drawPath[-17] - $drawPath[-15])) > REDUCE_TOLERANCE)) { return FALSE; }
#    if ((inches(abs($drawPath[-12] - $drawPath[-10])) > REDUCE_TOLERANCE) && (inches(abs($drawPath[-11] - $drawPath[-9])) > REDUCE_TOLERANCE)) { return FALSE; }
#    if ((inches(abs($drawPath[-6] - $drawPath[-4])) > REDUCE_TOLERANCE) && (inches(abs($drawPath[-5] - $drawPath[-3])) > REDUCE_TOLERANCE)) { return FALSE; }
    DebugPrint(sprintf("reduce rect thresh %5.5f vs: [%5.5f - %5.5f] = %5.5f, [%5.5f - %5.5f] = %5.5f, [%5.5f - %5.5f] = %5.5f, [%5.5f - %5.5f] = %5.5f, [%5.5f - %5.5f] = %5.5f, [%5.5f - %5.5f] = %5.5f, [%5.5f - %5.5f] = %5.5f, [%5.5f - %5.5f] = %5.5f", REDUCE_TOLERANCE,
        inches($drawPath[$x4]), inches($drawPath[-4]), inches(abs($drawPath[$x4] - $drawPath[-4])), inches($drawPath[$y4]), inches($drawPath[-3]), inches(abs($drawPath[$y4] - $drawPath[-3])),
        inches($drawPath[-18]), inches($drawPath[$x1]), inches(abs($drawPath[-18] - $drawPath[$x1])), inches($drawPath[-17]), inches($drawPath[$y1]), inches(abs($drawPath[-17] - $drawPath[$y1])),
        inches($drawPath[-12]), inches($drawPath[-16]), inches(abs($drawPath[-12] - $drawPath[-16])), inches($drawPath[-11]), inches($drawPath[-15]), inches(abs($drawPath[-11] - $drawPath[-15])),
        inches($drawPath[-6]), inches($drawPath[-10]), inches(abs($drawPath[-6] - $drawPath[-10])), inches($drawPath[-5]), inches($drawPath[-9]), inches(abs($drawPath[-5] - $drawPath[-9]))), 15);
    #replace 3 or 4 line segments with a rect:
    my $minX = min($drawPath[$x4], $drawPath[-18], $drawPath[-12], $drawPath[-6]);
    my $minY = min($drawPath[$y4], $drawPath[-17], $drawPath[-11], $drawPath[-5]);
    my $maxX = max($drawPath[$x4], $drawPath[-18], $drawPath[-12], $drawPath[-6]);
    my $maxY = max($drawPath[$y4], $drawPath[-17], $drawPath[-11], $drawPath[-5]);
    DebugPrint(sprintf("reducing last %d line segs to rect (%5.5f, %5.5f) .. (%5.5f, %5.5f)\n", min($drawPath[-2], 4), inches($minX), inches($minY), inches($maxX), inches($maxY)), 5);
    popshape(min($drawPath[-2], 4)); #remove 3-4 line segments
    push(@drawPath, ($minX, $minY, $maxX, $maxY, 1, "rect"));
    return TRUE;
}

#reduce last 4 line curves in drawing path to make a circle:
#full circle appears as follows (coordinates and stack position shown):
# x1[-40] y3[-39] x1[-38] y1[-37] x2[-36] y2[-35] x3[-34] y2[-33] c
# x3[-30] y2[-29] x4[-28] y2[-27] x5[-26] y1[-25] x5[-24] y3[-23] c
# x5[-20] y3[-19] x5[-18] y4[-17] x4[-16] y5[-15] x3[-14] y5[-13] c
# x3[-10] y5[-9] x2[-8] y5[-7] x1[-6] y4[-5] x1[-4] y3[-3] c
#parameters: none (uses globals)
#return value: true/false telling if a circle was found
sub reduceCircle
{
    our @drawPath; #globals

#    if ((scalar(@drawPath) < 2) || ($drawPath[-1] ne "curve") || ($drawPath[-2] < 3)) { DebugPrint(sprintf("non-circle: %d, %s, %d\n", scalar(@drawPath), $drawPath[-1], $drawPath[-2]), 5); return FALSE; } #subpath doesn't contain 4 curves
    if ((scalar(@drawPath) < 2) || ($drawPath[-1] ne "curve") || ($drawPath[-2] < 4)) { return FALSE; } #subpath doesn't contain 4 curves
    #verify that curves are really a circle (rather than just arcs or glyphs):
    if ((inches(abs($drawPath[-40] - $drawPath[-4])) > REDUCE_TOLERANCE) || (inches(abs($drawPath[-39] - $drawPath[-3])) > REDUCE_TOLERANCE)) { DebugPrint(sprintf("!circ [-40] %d != [-4] %d by %5.5f || [-39] %d != [-3] %d by %5.5f\n", $drawPath[-40], $drawPath[-4], inches(abs($drawPath[-40] - $drawPath[-4])), $drawPath[-39], $drawPath[-3], inches(abs($drawPath[-39] - $drawPath[-3]))), 5); return FALSE; }
    if ((inches(abs($drawPath[-30] - $drawPath[-34])) > REDUCE_TOLERANCE) || (inches(abs($drawPath[-29] - $drawPath[-33])) > REDUCE_TOLERANCE)) { DebugPrint(sprintf("!circ [-30] %d != [-34] %d by %5.5f || [-29] %d != [-33] %d by %5.5f\n", $drawPath[-30], $drawPath[-34], inches(abs($drawPath[-30] - $drawPath[-34])), $drawPath[-29], $drawPath[-33], inches(abs($drawPath[-29] - $drawPath[-33]))), 5); return FALSE; }
    if ((inches(abs($drawPath[-20] - $drawPath[-24])) > REDUCE_TOLERANCE) || (inches(abs($drawPath[-19] - $drawPath[-23])) > REDUCE_TOLERANCE)) { DebugPrint(sprintf("!circ [-20] %d != [-24] %d by %5.5f || [-19] %d != [-23] %d by %5.5f\n", $drawPath[-20], $drawPath[-24], inches(abs($drawPath[-20] - $drawPath[-24])), $drawPath[-19], $drawPath[-23], inches(abs($drawPath[-19] - $drawPath[-23]))), 5); return FALSE; }
    if ((inches(abs($drawPath[-10] - $drawPath[-14])) > REDUCE_TOLERANCE) || (inches(abs($drawPath[-9] - $drawPath[-13])) > REDUCE_TOLERANCE)) { DebugPrint(sprintf("!circ [-10] %d != [-14] %d by %5.5f || [-9] %d != [-13] %d by %5.5f\n", $drawPath[-10], $drawPath[-14], inches(abs($drawPath[-10] - $drawPath[-14])), $drawPath[-9], $drawPath[-13], inches(abs($drawPath[-9] - $drawPath[-13]))), 5); return FALSE; }
#    if ((inches(abs($drawPath[-40] - $drawPath[-4])) > REDUCE_TOLERANCE) || (inches(abs($drawPath[-39] - $drawPath[-3])) > REDUCE_TOLERANCE)) { return FALSE; } #x1,y1
#    if ((inches(abs($drawPath[-30] - $drawPath[-34])) > REDUCE_TOLERANCE) || (inches(abs($drawPath[-29] - $drawPath[-33])) > REDUCE_TOLERANCE)) { return FALSE; } #x2,y2
#    if ((inches(abs($drawPath[-20] - $drawPath[-24])) > REDUCE_TOLERANCE) || (inches(abs($drawPath[-19] - $drawPath[-23])) > REDUCE_TOLERANCE)) { return FALSE; } #x3,y3
#    if ((inches(abs($drawPath[-10] - $drawPath[-14])) > REDUCE_TOLERANCE) || (inches(abs($drawPath[-9] - $drawPath[-13])) > REDUCE_TOLERANCE)) { return FALSE; } #x4,y4

    #replace 4 curves with a circle:
    #kludge: my CAD software or PDF capture process is a little off for circles, so adjust it here
    my $minX = min($drawPath[-40], $drawPath[-30], $drawPath[-20], $drawPath[-10]) + CIRCLE_ADJUST_MINX;
    my $minY = min($drawPath[-39], $drawPath[-29], $drawPath[-19], $drawPath[-9]) + CIRCLE_ADJUST_MINY;
    my $maxX = max($drawPath[-40], $drawPath[-30], $drawPath[-20], $drawPath[-10]) + CIRCLE_ADJUST_MAXX;
    my $maxY = max($drawPath[-39], $drawPath[-29], $drawPath[-19], $drawPath[-9]) + CIRCLE_ADJUST_MAXY;
    if (inches(abs($maxX - $minX - $maxY + $minY)) > REDUCE_TOLERANCE) { mywarn("ellipse?"); return FALSE; } #ellipse or other shape; not implemented
    DebugPrint(sprintf("reducing last 4 arcs to circle, circle adjusted \"%d, %d, %d, %d\"\n", CIRCLE_ADJUST_MINX, CIRCLE_ADJUST_MINY, CIRCLE_ADJUST_MAXX, CIRCLE_ADJUST_MAXY), 5);
    popshape(4); #remove 4 arcs
    push(@drawPath, (($minX + $maxX)/2, ($minY + $maxY)/2, $maxX - $minX, 1, "circle"));
    return TRUE;
}


#convert very short traces to pads or holes:
sub convertPad
{
    our (@drawPath, %lineStyle, %visibleFillColor, $lastStrokeWeight); #globals

#    if (scalar(@drawPath) < 2) { return FALSE; } #avoid subscript error (short-circuit IF doesn't work); is this a bug?
#    if ((scalar(@drawPath) < 2) || ($drawPath[-1] ne "line") || ($drawPath[-2] < 3)) { DebugPrint(sprintf("non-rect: %d, %s, %d\n", scalar(@drawPath), $drawPath[-1], $drawPath[-2]), 5); return FALSE; } #subpath doesn't contain 4 line segments
    if ((scalar(@drawPath) < 2) || ($drawPath[-1] ne "line")) { return FALSE; } #subpath doesn't contain a line segment
#    if (($lineStyle{'cap'} != CAP_ROUND) && ($lineStyle{'cap'} != CAP_SQUARE)) { return FALSE; } #don't know how to make pad if not round or square
    if ($drawPath[-2] != 1) { return FALSE; } #only look at singleton lines; TODO: is this check needed?

    my ($xlen, $ylen) = (inches(abs($drawPath[-LINE_SHAPELEN + 0] - $drawPath[-LINE_SHAPELEN + 2])), inches(abs($drawPath[-LINE_SHAPELEN + 1] - $drawPath[-LINE_SHAPELEN + 3])));
    my ($xctr, $yctr, $r) = (($drawPath[-LINE_SHAPELEN + 0] + $drawPath[-LINE_SHAPELEN + 2]) / 2, ($drawPath[-LINE_SHAPELEN + 1] + $drawPath[-LINE_SHAPELEN + 3]) / 2, $lastStrokeWeight / 2); #max($xlen, $ylen) / 2);
    my $want_pad = ($xlen < TRACE_MINLEN) && ($ylen < TRACE_MINLEN); #treat very short line as pad (allows for arithmetic rounding errors)
    my $want_pad_circad = ((!$ylen && ($xlen <= inches(PAD_STROKE))) || (!$xlen && ($ylen <= inches(PAD_STROKE)))); #treat very short line as pad (allows for arithmetic rounding errors)
    DebugPrint(sprintf("latest line: from (%5.5f, %5.5f) to (%5.5f, %5.5f), x/y len (%5.5f, %5.5f) vs threshold %5.5f or %5.5f, convert to pad? %d or %d\n", inchesX($drawPath[-LINE_SHAPELEN + 0]), inchesY($drawPath[-LINE_SHAPELEN + 1]), inchesX($drawPath[-LINE_SHAPELEN + 2]), inchesY($drawPath[-LINE_SHAPELEN + 3]), $xlen, $ylen, TRACE_MINLEN, inches(PAD_STROKE), $want_pad? TRUE: FALSE, $want_pad_circad? TRUE: FALSE), 5);
#    my %LINE_STYLES; #= ( CAP_ROUND => "round", CAP_SQUARE => "square", ); #CAP_NONE => "butt(none)", ); #TODO: how to fix this?
#    $LINE_STYLES{CAP_ROUND} = "round";
#    $LINE_STYLES{CAP_SQUARE} = "square";
    if ((!$xlen && !$ylen) || $want_pad_circad) { DebugPrint(sprintf("converting to %s pad %s at xy (%5.5f, %5.5f) radius %5.5f\n", ($lineStyle{'cap'} == CAP_ROUND)? "round": ($lineStyle{'cap'} == CAP_SQUARE)? "square": "unknown", (!$xlen && !$ylen)? "stroke": "fill", inchesX($xctr), inchesY($yctr), inches($r)), 5); } #$LINE_STYLES{$lineStyle{'cap'}} || "unknown"

#Circad workaround: a hole is uniquely defined with zero-length stroke. Assume that cap style = 1 (round).
#    if (($drawPath[-1] eq "line") && ($drawPath[-2] == 1) && ($drawPath[-3] == $drawPath[-5]) && ($drawPath[-4] == $drawPath[-6]))
    if (!$xlen && !$ylen) #TODO: is this exactly equivalent to logic down below?
    {
#        $drawPath[-1] = "circle";   # this is a hole.
#        $drawPath[-3] = $lastStrokeWeight;  # check if this value is right
#        $drawPath[-4] = $drawPath[-5]; # swap X and Y... (?)
#        $drawPath[-5] = $drawPath[-6];
        splice(@drawPath, -LINE_SHAPELEN, LINE_SHAPELEN, $xctr, $yctr, 2 * $r, 1, "circle"); #pop rect, push circle; CAUTION: different shape sizes
        $visibleFillColor{'f'} = FALSE;
        return TRUE;
#		  fill();
#		  splice(@drawPath, -6, 6);  # consume 6 parameters because we forced a circle from a line.
#		  next;
#		  @drawPath = ();
    }
# Circad workaround: through-hole pads are defined as a short stroke (equal to "0.3" length in only one axis).
#    if  (($drawPath[-1] eq "line") && ($drawPath[-2] == 1) && ((($drawPath[-3] == $drawPath[-5]) && (abs($drawPath[-4] - $drawPath[-6]) <= PAD_STROKE)) || 
#        (($drawPath[-4] == $drawPath[-6]) && (abs($drawPath[-3] - $drawPath[-5]) <= PAD_STROKE))))
    if ($want_pad_circad)
    {
        $visibleFillColor{'f'} = TRUE;
        if ($lineStyle{'cap'} == CAP_SQUARE) # cap style "2" is a square aperture
        {
#            $drawPath[-1] = "rect";
#  the following code lines establish the proper rectangle size, as the rectangular pad is zero girth from the normal params passed
#            if ($drawPath[-3] >= $drawPath[-5])
#            {
#                $drawPath[-3] = $drawPath[-3]+$lastStrokeWeight/2;
#                $drawPath[-5] = $drawPath[-5]-$lastStrokeWeight/2;
#            }
#            else
#            {
#                $drawPath[-3] = $drawPath[-3]-$lastStrokeWeight/2;
#                $drawPath[-5] = $drawPath[-5]+$lastStrokeWeight/2;
#            }
#            if ($drawPath[-4] >= $drawPath[-6])
#            {
#                $drawPath[-4] = $drawPath[-4]+$lastStrokeWeight/2;
#                $drawPath[-6] = $drawPath[-6]-$lastStrokeWeight/2;
#            }
#            else
#            {
#                $drawPath[-4] = $drawPath[-4]-$lastStrokeWeight/2;
#                $drawPath[-6] = $drawPath[-6]+$lastStrokeWeight/2;
#            }
            splice(@drawPath, -LINE_SHAPELEN, LINE_SHAPELEN, $xctr - $r, $yctr - $r, $xctr + $r, $yctr + $r, 1, "rect"); #pop rect, push circle
            return TRUE;
#			   fill();
#			   if (popshape()) { next; }
#			   @drawPath = ();
        }
        else # hopefully this means its a "round" pad.
        {
#            $drawPath[-1] = "circle";   # this is a round pad (?)
#            $drawPath[-3] = ($drawPath[-3]+$drawPath[-5])/2;  # center the pad
#            $drawPath[-5] = ($drawPath[-4]+$drawPath[-6])/2;  # center the pad and swap
#            $drawPath[-4] = $drawPath[-3];  # the X and Y coordinates
#            $drawPath[-3] = $lastStrokeWeight;  # check if this value is right
            splice(@drawPath, -LINE_SHAPELEN, LINE_SHAPELEN, $xctr, $yctr, 2 * $r, 1, "circle"); #pop rect, push circle; CAUTION: different shape sizes
            return TRUE;
#			 fill();
#			 splice(@drawPath, -6, 6);  # consume 6 parameters because we forced a circle from a line.
#			 next;
#			 @drawPath = ();
        }
    }

    return FALSE; #don't need below logic?
    if (!$want_pad) { return FALSE; }
#    if (!$xlen) { $drawPath[-6 + 0] -= TRACE_MINLEN / 2; $drawPath[-6 + 2] += TRACE_MINLEN / 2; $xlen = TRACE_MINLEN; }
#    if (!$ylen) { $drawPath[-6 + 1] -= TRACE_MINLEN / 2; $drawPath[-6 + 3] += TRACE_MINLEN / 2; $ylen = TRACE_MINLEN; }
#    popshape();
#    push(@drawPath, ($xctr - $xlen / 2, $yctr - $ylen / 2, $xctr + $xlen / 2, $yctr + $ylen / 2, 1, "rect"));
    if ($lineStyle{'cap'} == CAP_SQUARE)
    {
#        splice(@drawPath, -2, 2, 1, "rect"); #convert line to rect (overwrite shape + count, leave coords as-is)
#        splice(@drawPath, -6, 4, min($drawPath[-6], $drawPath[-4]), min($drawPath[-5], $drawPath[-3]), max($drawPath[-6], $drawPath[-4]), max($drawPath[-5], $drawPath[-3])); #reorient rect
        splice(@drawPath, -LINE_SHAPELEN, LINE_SHAPELEN, $xctr - $r, $yctr - $r, $xctr + $r, $yctr + $r, 1, "rect"); #pop line, push rect (same shape size)
        return TRUE;
    }
    if ($lineStyle{'cap'} == CAP_ROUND)
    {
#        splice(@drawPath, -6, 6); #pop rect
#        splice(@drawPath, -6, 4, $xctr - $r, $yctr - $r, $xctr + $r, $yctr + $r); #push circle
        splice(@drawPath, -LINE_SHAPELEN, LINE_SHAPELEN, $xctr, $yctr, 2 * $r, 1, "circle"); #pop rect, push circle; CAUTION: different shape sizes
        return TRUE;
    }
#    $line = "f"; #pretend we saw a fill command and reuse existing logic to render pad or hole
    return FALSE;
}


#count #shapes on drawing subpath:
#parameters: type of shape wanted
#return value: a count of number of that shape found in drawing path
sub numshapes
{
    our @drawPath; #globals

    my ($wanted) = @_; #shift();
    if (scalar(@drawPath) < 1) { return 0; }
    return ($drawPath[-1] eq $wanted)? $drawPath[-2]: 0; #count #consecutive line segments (to help detect rectangles)
}


#return desc of top shape (for debug messages only):
sub topshape
{
    our (@drawPath, %SHAPELEN); #globals

    if (!exists($SHAPELEN{$drawPath[-1]})) { mywarn("unhandled shape type: $drawPath[-1]"); }
    return sprintf("$drawPath[-1] (%5.5f, %5.5f)", inchesX($drawPath[-$SHAPELEN{$drawPath[-1]}]), inchesY($drawPath[1 - $SHAPELEN{$drawPath[-1]}]));
}


#pop a shape from drawing path:
#parameters: number of shapes to remove from drawing path (optional, defaults to 1)
#return value: none (uses globals)
sub popshape
{
    our (@drawPath, %SHAPELEN); #globals

    my $retval = FALSE;
    for (my ($numsh) = scalar(@_)? @_: (1); $numsh > 0; --$numsh) #consume next shape
    {
        if (scalar(@drawPath) < 2) { mywarn(sprintf("whoops %d < $numsh", scalar(@drawPath))); return $retval; } #probably a bug
        my $num_elts = $SHAPELEN{$drawPath[-1]};
        DebugPrint(sprintf("pop %s (%d elements) of %d shape(s) from list of %d elements\n", $drawPath[-1], $num_elts, $numsh, scalar(@drawPath)), 5); #NOTE: each shape is 5/6/10 elements
        splice(@drawPath, -$num_elts, $num_elts); #pop()
        $retval = TRUE;
    }
    return $retval;
}


#decode PDF1.4 flate encoding:
#parameters: compressed stream
#return value: uncompressed stream
sub decompress
{
    our ($outputDir, $grab_streams); #globals

    my ($buf, $srcpath) = @_; #shift();
    #don't care if /Length is there; just scan for "endstream"
#    while ($buf =~ m/<<.*?\/FlateDecode.*?>>\r?\nstream\r?\n((\n|\r|.)*)endstream/mg) #expand compressed streams
#too greedy; try to get minimum match:
#    while ($buf =~ m/<<.*?\r?\n?.*?\/FlateDecode.*?\r?\n?>>\r?\n?stream\r?\n((\n|\r|.)*)endstream/mg) #expand compressed streams; \r \n seems to be optional, or can occur multiple times
#    while ($buf =~ m/<<.*?\/FlateDecode.*?>>\r?\n?stream\r?\n(.*?)endstream/mgs) #expand compressed streams; \r \n seems to be optional, or can occur multiple times
#still not quite right, but closer to being correct:
#CAUTION: found a space after "<< >>", so allow spaces at various places:
    DebugPrint(sprintf("decompressing '$srcpath' (T+%f) ...", time() - $runtime), 8);
    while ($buf =~ m/<<.*?>>\s*\r?\n?stream\s*\r?\n(.*?)\s*\r?\n?\s*endstream/mgs) #expand compressed streams; \r \n seems to be optional, or can occur multiple times
    {
#        DebugPrint("stream found\n", 1);
        if (++$grab_streams > 100) { DebugPrint(sprintf("too many streams found: %d", $grab_streams), 1); return $buf; } #avoid filling up file system
        my ($compressed, $stofs, $enofs, $st_first, $en_first) = ($1, $-[0], $+[0], $-[1], $+[1]); #NOTE: [0] = entire pattern, [1] = first subpattern, etc.
#my $comp = $compressed; $comp =~ s/\n/\\n/g; $comp =~ s/\r/\\r/g;
#DebugPrint("match $comp", 1);
        my $before = substr($buf, $st_first - 8, 8); $before =~ s/\n/\\n/g; $before =~ s/\r/\\r/g;
        my $after = substr($buf, $en_first, 8); $after =~ s/\n/\\n/g; $after =~ s/\r/\\r/g;
        DebugPrint("stream#$grab_streams: start ofs $stofs $st_first, end ofs $enofs $en_first, inlen: " . length($compressed) . " '... $before (data) $after ...'\n", 6);
#        DebugPrint("stream[$grab_streams] inlen: " .  . "\n", 5);

        my $chkbuf = substr($buf, $stofs, $enofs - $stofs);
        if (substr($chkbuf, 0, 2) ne "<<") { mywarn("bad stofs1 " . substr($chkbuf, 0, 2)); }
        if (substr($buf, $stofs, 2) ne "<<") { mywarn("bad stofs2 " . substr($buf, $stofs, 2)); }
        if (substr($chkbuf, length($chkbuf) - 9, 9) ne "endstream") { mywarn("bad enofs1 " . substr($chkbuf, length($chkbuf) - 9, 9)); }
        if (substr($buf, $enofs - 9, 9) ne "endstream") { mywarn("bad enofs2 " . substr($buf, $enofs - 9, 9)); }
#could occur        if (substr($chkbuf, 2, length($chkbuf) - 2) =~ m/<</gs) { mywarn("parser broken1: " . $-[0]); }
        if (substr($chkbuf, 0, length($chkbuf) - 2) =~ m/endstream/gs) { mywarn("parser broken2: " . $-[0]); }
        if ($chkbuf !~ /FlateDecode/mgs) { DebugPrint("stream#$grab_streams not compressed\n", 1); next; } #not compressed

        my ($df, $instat) = inflateInit();
        my ($decompressed, $outstat) = $df->inflate($compressed);
        DebugPrint("stream outlen: " . length($decompressed) . ", stat in: $instat, out: $outstat\n", 6);
        if ($decompressed =~ m/[^\r\n\x20-\x7e]/) { my $bad_char = ord(substr($decompressed, $-[0], 1)); mywarn("decompressed stream still has junk char @ $-[0]: $bad_char", 1); }
        if (WANT_STREAMS) #save decompressed stream to text file (for easier debug)
        {
            my ($vol, $dir, $srcfile) = File::Spec->splitpath($srcpath);
            $srcfile =~ s/\.pdf$//i; #drop src file extension to avoid confusion
            my $filename = "stream#$grab_streams($srcfile).txt"; #show where it came from within file name
            open my $outstream, ">$outputDir$filename";
            print $outstream $decompressed;
            close $outstream;
#            ++$numfiles_out;
            $did_file{$filename} = TRUE;
            DebugPrint("wrote stream#$grab_streams len " . length($decompressed) . " to $filename\n", 5);
        }
        DebugPrint(sprintf("outbuf: old len " . length($buf) . " => $stofs header + " . length($compressed) . " -> " . length($decompressed) . " decompressed stream + %d trailer \n", length($buf) - $enofs), 6);
        #substr($buf, $stofs, $enofs) = $decompressed . "\n";
        $buf = substr($buf, 0, $stofs) . "stream\r\n" . $decompressed . "\nendstream\r\n" . substr($buf, $enofs);
    }
#PDF1.3 can have "<< /FlateDecode >> BDC0 ... EMC" segments so decompress them also
#    while ($buf =~ m/\/FlateDecode >>\r?\nBDC0\r?\n(.*?)EMC/mgs)
#    {
#        my ($compressed, $stofs, $enofs) = ($1, $-[0], $+[0]); #NOTE: [0] = entire pattern, [1] = first subpattern, etc.
#        my ($df, $instat) = inflateInit();
#        my ($decompressed, $outstat) = $df->inflate($compressed);
#        DebugPrint(sprintf("found compressed seg, inlen %d, outlen %d, stat in: $instat, out: $outstat\n", length($compressed), length($decompressed)), 6);
#        $buf = substr($buf, 0, $stofs) . "BDC0\r\n" . $decompressed . "\nEMC\r\n" . substr($buf, $enofs);
#    }
    DebugPrint(sprintf("... decompressed '$srcpath' (T+%f) ...", time() - $runtime), 8);

    pos($buf) = 0; #reset regex search position
    if ($buf =~ m/\/FlateDecode/gs) { mywarn("parser didn't decompress stream; please report this problem!"); exit; } #sanity check; output will be useless if stream was not extracted correctly
    return $buf;
}


#rotate X/Y coordinates according to page orientation:
#parameters: x, y coordinates
#return value: rotated x, y coordinates
sub rotate
{
    our ($rot, %pcbLayout); #globals

    my ($x, $y) = @_;
    if ($rot == 90) { return ($y, $pcbLayout{'ymax'} - ($x - $pcbLayout{'ymin'})); }
    if ($rot == 180) { return ($pcbLayout{'xmin'} + $pcbLayout{'xmax'} - $x, $pcbLayout{'ymin'} + $pcbLayout{'ymax'} - $y); }
    if ($rot == 270) { return ($pcbLayout{'xmax'} - ($y - $pcbLayout{'ymin'}), $x); }
    return ($x, $y); #treat everything else as 0
}


###########################################################################
#Generate output commands and files:
###########################################################################

#set layer polarity for additive/subtractive areas:
#parameters: 'f' or 's' to select which polarity wanted
#return value: none (uses globals)
sub SetPolarity
{
    our ($layerPolarity, %visibleFillColor, $body); #globals

    my ($which) = @_; #shift();
    if ($layerPolarity == $visibleFillColor{$which}) { if ($visibleFillColor{$which}) { return; }} #NOTE: seems like %LPC is not persistent, so always generate it when needed
    DebugPrint(sprintf("polarity: $which was %d %s, is now %d %s\n", $layerPolarity, $layerPolarity? "visible": "hidden", $visibleFillColor{$which}, $visibleFillColor{$which}? "visible": "hidden"), 4);
    if (!$visibleFillColor{$which}) #white (invisible)
        { $body .= "%LPC*%\n"; } #subtractive: remove shapes that follow
    else #visible
        { $body .= "%LPD*%\n"; } #additive: add shapes that follow
#    my ($package, $filename, $line, $sub) = caller; #(1); #info about caller
#    $body .= "G04 polarity from $line\n";
    $layerPolarity = $visibleFillColor{$which};
}

#set round or square aperture according to current line cap style:
sub SetAperture_shape
{
    our %lineStyle; #globals
    my ($type, $where, $size) = @_;

    return ($lineStyle{'cap'} == CAP_ROUND)? SetAperture($type, $where, $size): #use round aperture
        ($lineStyle{'cap'} == CAP_SQUARE)? SetAperture($type, $where, $size, $size): #use square aperture
        mywarn("which aperture $lineStyle{'cap'}?");
}

#select new aperture:
#modified to only issue tool command if needed
#modified to handle rectangular apertures
#example round aperture select: %ADD13C,0.0705*%
#example octagonal aperture: %ADD11OC8,0.0860*% (not implemented)
#example rectangular aperture select: %ADD12R,0.0860X0.0860*%
#parameters: type (pad/hole/mask/fill-any), size (diameter or width), height (optional, only for rectangular apertures)
#return value: newly selected aperture#
sub SetAperture #GetAperture
{
    our (%apertures, $lastAperture, %lineStyle, $body); #globals

    my $wanttype = shift(); #choose standard trace (stroke), pad, or hole size; any type can be used for fill
    my $where = shift(); #for debug only
    # Get the number to convert
    my $input = shift(); #(@_);
#    my ($wanttype, $where, $input) = @_;
    # Convert it to inches
    my $inches = inches($input);
    my $override = CAP_OVERRIDE? "cap style": "caller";

    my $want_round = !scalar(@_); #extra param passed for rect
    if (($wanttype ne "m") && $want_round && ($lineStyle{'cap'} != CAP_ROUND))
    {
        mywarn("caller wants round aperture at $where, but line cap style is square: ${override} overrides");
        if (CAP_OVERRIDE) { $want_round = FALSE; } #override caller
        unshift(@_, $inches);
    }
    elsif (($wanttype ne "m") && !$want_round && ($lineStyle{'cap'} == CAP_ROUND))
    {
        mywarn("caller wants rect aperture at $where, but line cap style is round: ${override} overrides");
        if (CAP_OVERRIDE) { $want_round = TRUE; } #override caller
    }
#DebugPrint("SetApert: type $wanttype, want size $input => inches $inches\n", 5);
#TODO: use line cap style to choose square vs. round?
    $inches = StandardTool($wanttype, $inches); #use standard tool sizes
    if (!$want_round) #scalar(@_)) #width + height passed: rectangle
    {
        my ($w, $h) = ($inches, shift()); #width (inches), height (points)
        $h = (abs($h - $input) <= 1)? $inches: StandardTool($wanttype, inches($h));
        #no if (abs($w - $h) >= .001) { mywarn("rect aperture: $w x $h"); } #can photoplotter apertures really be rectangular, or only square?
        #no $inches = sprintf("R,%5.5fX%5.5f", min($w, $h), max($w, $h)); #use minimum dimension and drag it to form rectangle
        $inches = sprintf("R,%5.5fX%5.5f", $w, $h);
        DebugPrint(sprintf("rect aperture %5.5f x %5.5f \"%d x %d\", tool '$inches'\n", $w, $h, points($w), points($h)), 5);
    }
    else #diameter passed: round (as before)
    {
        $inches = sprintf("C,%5.5f", $inches); #put shape in aperture list to distinguish rect vs. circular
        DebugPrint(sprintf("circular aperture %5.5f \"$input\", tool '$inches'\n", inches($input)), 5);
    }

    # Look through all previously defined apertures to find the one we want
    if (!exists($apertures{$inches})) #add new aperture; changed to a hash map
    {
        my $nextaper = scalar(keys %apertures);
        #are aperture# checks needed for digital photoplotters?
        if (APERTURE_LIMIT && ($nextaper >= APERTURE_LIMIT)) { mywarn("too many apertures/tools?"); } #pcb is too complex?
        if ($nextaper >= 20) { $nextaper += 40; } #CAUTION: aperture# jumps from 29 to 70    
        $nextaper = sprintf("D%u", $nextaper + 10); #add next aperture#
        $apertures{$inches} = $nextaper;
        DebugPrint(sprintf("add aperture: $nextaper, actual size $inches, requested size %5.5f \"$input\"\n", inches($input)), 5);
    }
    my $newaper = $apertures{$inches};

    if ($newaper ne $lastAperture) #only emit tool command if aperture changed
    {
        DebugPrint(sprintf("use aperture $newaper: actual size $inches, requested size %5.5f \"$input\", wanted '$wanttype'\n", inches($input)), 5);
        $body .= "G54$newaper*\n"; #NOTE: some docs say "G54" is optional, but put in there just in case it's not
        $lastAperture = $newaper;
    }
    return $lastAperture;
}

#set drill tool:
#modified to only issue tool command if needed
#parameters: drill size
#return value: newly selected tool#
sub SetDrillAperture #GetDrillAperture
{
    our (%drillApertures, $currentDrillAperture, %drillBody); #globals

    # Get the number to convert
    my ($input) = @_; #shift(); #(@_);

    # Convert it to inches
    my $inches = inches($input);
    $inches = StandardTool('h', $inches); #use standard tool sizes
    $inches = sprintf("%4.4f", $inches); #use 2.4 format instead of 2.3

    # Look through all previously defined apertures to find the one we want
    if (!exists($drillApertures{$inches})) #add new aperture; changed to a hash map
    {
        my $newtool = sprintf("T%02u", scalar(keys %drillApertures) + 1); #add next tool#
        $drillApertures{$inches} = $newtool;
        $drillBody{$newtool} = ""; #create new list of holes for this drill size
        DebugPrint(sprintf("add drill tool: $newtool, actual size $inches, requested size %5.5f \"$input\"\n", inches($input)), 5);
    }

    $currentDrillAperture = $drillApertures{$inches};
    return $currentDrillAperture;
}

#map to standard tool size:
#parameters: tool type (pad/hole/mask/fill-any/exact), tool size
#return value: adjusted tool size
sub StandardTool
{
    my ($wanttype, $size) = @_;

    if ($wanttype eq 'x') { return $size; } #no mapping, use exact size
    DebugPrint("std tool: want type $wanttype, want size $size", 18);
    for (my ($i, $wantsize, $bestdelta) = (0, $size, MAXINT); $i < scalar((TOOL_SIZES)); ++$i)
    {
        my $tooltype = ((TOOL_SIZES)[$i] < 0)? 'h': ($i + 1 >= scalar((TOOL_SIZES)))? 't': ((TOOL_SIZES)[$i + 1] > 0)? 't': 'p'; #pad sizes (+ve) are followed by a drill size (-ve)
        if (($wanttype eq 'm') && ($tooltype eq 'p')) { $tooltype = 'm'; } #treat pads as matches for masks
        if (($wanttype ne 'f') && ($tooltype ne $wanttype)) { next; } #limit trace (stroke) and pads to standard sizes
        elsif (($wanttype eq 'f') && ($tooltype eq 'h')) { next; } #fill can use any aperture, but not drill tools
        my $delta = abs($wantsize - abs((TOOL_SIZES)[$i]));
        if ($delta >= $bestdelta) { next; } #no better than current choice
        DebugPrint(sprintf("check tool[$i/%d]: type $tooltype, size %5.5f, delta %5.5f from requested size %5.5f, best %5.5f, type $tooltype, wanted $wanttype, keep? %s\n", scalar((TOOL_SIZES)), abs((TOOL_SIZES)[$i]), $delta, $wantsize, $bestdelta, $delta < $bestdelta), 18);
        ($size, $bestdelta) = (abs((TOOL_SIZES)[$i]), $delta);
        if (!$delta) { last; } #exact match; won't find anything better than this so stop looking
    }
    if ($wanttype eq 'm') { $size += SOLDER_MARGIN; } #enlarge pad for mask
    DebugPrint("std tool: chose tool size $size", 18);
    return $size;
}

#refill copper areas where final holes remain:
#Is this needed for correct plated holes?
#parameters: none (uses globals)
#return value: none (uses globals)
sub refillholes
{
    our (%holes, $body); #globals

    DebugPrint(sprintf("unfilled holes to check: %d\n", scalar(keys %holes)), 5);
    foreach my $xy (keys %holes)
    {
        my $drillsize = $holes{$xy};
        if ($body !~ m/\nG04 drill $drillsize $xy\*\n(.|\r|\n)*\nG04 \/drill $drillsize $xy\*\n/m) #find copper fill commands
        {
            mywarn("can't find copper refill area for drill $drillsize, location $xy"); #probably a bug
            next;
        }
        my ($refill, $stofs, $enofs) = (substr($body, $-[0], $+[0] - $-[0]), $-[0], $+[0]);
        my $str = substr($refill, 0, 20) . "...";
        $str =~ s/\r?\n/\\n/g;
        DebugPrint(sprintf("refill copper for hole $drillsize at $xy, was: %d:%d..%d:'%s'\n", length($refill), $stofs, $enofs, $str), 10);
        my $bodylen = length($body); #for debug
        $refill =~ s/\n(X-?\d+)?(Y-?\d+)?D0[123]\*\n/\n/gs; #remove move/line/flash commands only; leave tool, polarity changes intact to preserve state for following commands
        $body = substr($body, 0, $stofs) . $refill . substr($body, $enofs);
        $bodylen -= length($body); #for debug
        DebugPrint(sprintf("body shrunk by %d after refill hole, len is now: %d:'%s'\n", $bodylen, length($refill), substr($refill, 0, 20) . "..."), 15);
    }
    DebugPrint(sprintf("unfilled holes remaining: %d\n", scalar(keys %holes)), 5);
}

#generate copper layer:
#same logic is used for silk screen and solder mask layers, so a description is passed in
#parameters: layer type (copper/mask/silk)
#return value: none (uses globals)
sub copper
{
    our (@layerTitles, $currentLayer, %did_file, %apertures, $body, $outputDir); #globals
    my ($desc) = @_; #shift(); #top/bottom-copper/mask/silk

    if ($body eq "")
    {
        DebugPrint("no $desc contents for $layerTitles[$currentLayer]?\n", 2);
        return;
    }

    # Leading zero suppression, absolute coordinates, format=2.4
    # (Seems like this should be NO zero suppression, but doesn't validate
    # correctly otherwise.)
    my $header = sprintf("G04 Pdf2Gerb %s: $layerTitles[$currentLayer] at %s *\n", VERSION, scalar localtime); #show when/how created
    $header .= "%FSLAX24Y24*%\n"; #2.4 format, absolute, no decimal
    #even though solder mask is inverted, it looks like we don't need to set it that way?
    $header .= "%IPPOS*%\n"; #image polarity; always use positive, even for solder masks?
#G75*
#G70*
#%OFA0B0*%
#%FSLAX24Y24*%
#%IPPOS*%
#%LPD*%
#%AMOC8*
#5,1,8,0,0,1.08239X$1,22.5*
#%        
    # Measurements are in inches or metric
    $header .= METRIC? "G71*\n%MOMM*%\n": "G70*\n%MOIN*%\n"; #allow metric

    #write aperture list:
    my %apersizes = reverse %apertures; #allow fast lookup of aperture# -> size
    foreach my $aper (sort values %apertures) #write out aperture list in tool# order
    {
        $header .= "%AD$aper$apersizes{$aper}*%\n"; #add to aperture list
        DebugPrint("add aperture $aper to $desc header\n", 5);
    }

    $header .= "G01*\n"; #moved to here; must be last command before body
    $header .= "G54D10*\n"; #select tool in case there are no traces (avoids ViewPlot D00 message for outline file)
    $body = Panelize($body); #apply panelization

    # stripNoise - remove groups of
    #    %LPC*%
    #    G54xx
    #    G04xxxxx
    # as these is a noise triple that doesn't do anything (except screw up FlatCAM!!) - applies only to copper layers - cyo
    if ($desc =~ m/-?copper/i) { $body = stripNoise($body); }

    $body .= "M02*\n"; #moved to here; must be last command

    # Write this out to a file
    my $filename = basename($layerTitles[0]); #$layerTitles[$currentLayer]; #use first layer name for output files
    $filename =~ s/-?(top|bottom|copper|silk|mask)//gi; #top and bottom drill files are the same, so they don't need to be named that way; remove other extraneous type names also
#    if ($desc eq "outline") { $filename =~ s/-?top|-?bottom|-?silk//; } #strip top/bottom/silk from filename before adding desc back in
#    if ($filename !~ m/(^|\W)\Q$desc\E$/i) { $filename .= "-$desc"; } #append desc if not in file name
#    if ($filename !~ m/-?\Q$desc\E$/i) { $filename .= "-$desc"; } #append desc if not in file name
    if ($desc =~ m/-?(top|bottom)/i) { $filename .= "-$1"; }
    if ($desc =~ m/-?(silk|copper|mask)/i) { $filename .= "-$1"; }
    if ($desc =~ m/-?(drill|outline)/i) { $filename .= "-$1"; $filename =~ s/-?maybe//i; }
    DebugPrint("copper filename padded: $filename\n", 1);
    if ($did_file{$filename}) { return; }

    DebugPrint("$desc layer[$currentLayer] $layerTitles[$currentLayer] $filename " . GerbExt($filename) . "\n", 10);
    $filename = GerbExt($filename); #suggested file extension

#    my $which = ($filename =~ m/-?top/i)? "top ": ($filename =~ m/-?bottom/i)? "bottom ": "";
    DebugPrint("${\(GREEN)}Writing $desc layer to $filename ...${\(RESET)}", 0);
    open my $outputFile, ">$outputDir$filename";
    print $outputFile $header; #avoid big string concat (split into multiple stmts)
    print $outputFile $body;
    close $outputFile;
#    ++$numfiles_out; #might be dup (silk)
    $did_file{$filename} = TRUE;
    DebugPrint(sprintf("wrote %d bytes header + %d bytes body to $filename\n", length($header), length($body)), 2);
}

#generate solder mask:
#For each pad, enlarge and flash onto a negative layer.
#NOTE: This actually generates another copper layer and then reuses the copper writing logic.
#Mask commands were generated at the same time as the pads; here we just concatenate them all together.
#parameters: none (uses globals)
#return value: none (uses globals)
sub solder
{
    our (%holes, %masks, %visibleFillColor, $lastAperture, %apertures, $body); #globals

    my ($desc) = @_; #shift(); #top/bottom
    if (!scalar(keys %masks)) { return; }

    ($body, %apertures) = ("", ());
    DebugPrint(sprintf("starting solder mask, pads: %d, holes: %d\n", scalar(keys %masks), scalar(keys %holes)), 5);
    my %maskxy = reverse %masks;
    foreach my $mask (values %masks)
    {
        my $xy = $maskxy{$mask};
        if ($mask =~ m/^(\d+)\n/s) { SetAperture('m', "mask $mask", $1); } #round
        elsif ($mask =~ m/^(\d+),(\d+)\n/s) { SetAperture('m', "mask $mask", $1, $2); } #square
        else { mywarn("bad mask: '$mask'"); next; } #probably a bug
        $mask = substr($mask, $+[0]); #drop first line, keep remaining commands
        DebugPrint(sprintf("solder mask: aper $lastAperture, $xy '$xy', body '$mask', hole? %d\n", exists($holes{$xy})), 5);
        $body .= $mask;
    }

    copper("$desc mask"); #reuse copper layer writing logic
}
    
#generate outline layer:
#NOTE: This actually generates another copper layer and then reuses the copper writing logic.
#parameters: none (uses globals)
#return value: none (uses globals)
sub edges
{
    our (%pcbLayout, @drawPath, %lineStyle, %apertures, $body, $did_file, $is_AI, $offsetX, $offsetY); #globals
    my ($svx, $svy);

#    if (exists($did_file{"outline"})) { return; } #only need to create once; copper() will check this
    for my $filename (keys %did_file) { if ($filename =~ m/outline/i) { return; }}

    ($body, %apertures) = ("", ());

    if ($lineStyle{'cap'} == CAP_ROUND) { SetAperture('x', "outline", 1); }
    else { SetAperture('x', "outline", 1, 1); }
    @drawPath = ($pcbLayout{'xmin'}, $pcbLayout{'ymin'}, $pcbLayout{'xmax'}, $pcbLayout{'ymax'}, 1, "rect");
    if ($is_AI) #don't translate outline for AI
    {
        @drawPath = (0, 0, $pcbLayout{'xmax'} - $pcbLayout{'xmin'}, $pcbLayout{'ymax'} - $pcbLayout{'ymin'}, 1, "rect");
        ($svx, $svy) = ($offsetX, $offsetY);
        ($offsetX, $offsetY) = (0, 0);
    }
    outline();

    copper("outline"); #reuse copper layer writing logic
#redundant    $did_file{"outline"} = TRUE;
    if ($is_AI) { ($offsetX, $offsetY) = ($svx, $svy); }
}

#generate drill file:
#parameters: none (uses globals)
#return value: none (uses globals)
sub drill
{
    our (@layerTitles, $currentLayer, %drillApertures, %drillBody, $outputDir, $did_file); #globals

    if (exists($did_file{"drill"})) { return; } #only need to create once
    if (!scalar(keys %drillBody))
    {
        DebugPrint("no drill layer for $layerTitles[$currentLayer]?\n", 2);
        return;
    }

    # Write the drill header, format=2.3 or 2.4
    my $drillHeader = sprintf("G04 Pdf2Gerb %s (%s fmt): $layerTitles[$currentLayer] at %s *\n", VERSION, DRILL_FMT, scalar localtime); #show when/how created
    $drillHeader .= "%\nM48\nM72\n"; #moved from above
#??    $drillHeader = "%FSLAX24Y24*%\n" . $drillHeader; #make it 2.4, absolute, no decimal

    #write tool list:
    #hole lists are grouped by tool size to minimize tool swapping:
    my $body = "";
    my %drillsizes = reverse %drillApertures; #allow fast lookup of drill tool# -> size
    foreach my $tool (sort keys %drillBody) #write out drill list in tool# order
    {
        if ($drillBody{$tool} eq "") { next; } #skip unused tools
        DebugPrint("generating drill list for tool $tool\n", 15);
        $drillHeader .= $tool . "C$drillsizes{$tool}\n"; #add to tool list
        if (DUP_DRILL1 && ($body eq "")) #kludge: ViewPlot doesn't want to load small drill files so duplicate first tool
        {
#            my $first = (split /\n/, $drillBody{$tool})[0];
            $body .= "$tool\n" . $drillBody{$tool};
        }
        $body .= "$tool\n" . $drillBody{$tool}; #add size and list of holes to drill
    }
    $drillHeader .= "%\n";
    $body = Panelize($body); #apply panelization
#convert drill 2.4 to 2.3 format:
#do this *after* Panelize, otherwise x/y panelization will be messed up
#does this only need to be done for drill file?
    if (DRILL_FMT eq '2.3')
    {
        my @xylines = split /\n/, $body;
        foreach my $xyline (@xylines) #adjust all X + Y coordinates
        {
            if ($xyline =~ m/X(-?\d+)/g)
            {
                my ($stofs, $enofs, $xval) = ($-[0], $+[0], $1/10000);
                $xval = sprintf("X%06.3f", $xval);
                $xval =~ s/\.//;
                $xyline = substr($xyline, 0, $stofs) . $xval . substr($xyline, $enofs);
            }
            if ($xyline =~ m/Y(-?\d+)/g)
            {
                my ($stofs, $enofs, $yval) = ($-[0], $+[0], $1/10000);
                $yval = sprintf("Y%06.3f", $yval);
                $yval =~ s/\.//;
                $xyline = substr($xyline, 0, $stofs) . $yval . substr($xyline, $enofs);
            }
        }
        $body = join("\n", @xylines). "\n";
    }
    $body .= "T00\nM30\n"; #moved to here; must be last command

    my $filename = "$layerTitles[0]-drill(DRD).txt"; #use first layer name for output file name
    $filename =~ s/-?(top|bottom|copper|silk|mask|maybe)//gi; #top and bottom drill files are the same, so they don't need to be named that way; remove other extraneous type names also
    DebugPrint("${\(GREEN)}Writing drill file to $filename ...${\(RESET)}", 0);
    open my $outputFile, ">$outputDir$filename";
    print $outputFile $drillHeader; #avoid big string concat (split into multiple stmts)
    print $outputFile $body;
    close $outputFile;
#    ++$numfiles_out;
    $did_file{"drill"} = TRUE;
    DebugPrint(sprintf("wrote %d bytes header + %d bytes drill body to $filename\n", length($drillHeader), length($body)), 2);
}

#apply panelization:
#The code below just updates the final results with updated coordinates because this feature was an after-thought.
#It would have been more efficient to store the original drawing commands and then update the coordinates directly.
#Performance isn't too bad, so this can be used as-is.
#NOTE: final X/Y coordinates are updated rather than using the more accurate pre-scaled values.
#However, since we are just adding offsets, the results are still reasonably accurate.
#parameters: layer body
#return value: panelized layer body
sub Panelize
{
    our (%pcbLayout); #globals
    my ($body) = @_;

    if ((PANELIZE->{'x'} * PANELIZE->{'y'} > 1) || !PANELIZE->{'overhangs'})
    {
        DebugPrint(sprintf("panelize %d x %d, overhang? %d ...\n", PANELIZE->{'x'}, PANELIZE->{'y'}, PANELIZE->{'overhangs'}), 2);
        my ($minX, $minY, $maxX, $maxY) = (inchesX($pcbLayout{'xmin'}), inchesY($pcbLayout{'ymin'}), inchesX($pcbLayout{'xmax'}), inchesY($pcbLayout{'ymax'}));
        my ($panels, $psubs, $ptime) = ("", 0, time()); #Time::HiRes::gettimeofday(); #measure execution time for panelization
        for (my $px = 0; $px < PANELIZE->{'x'}; ++$px)
        {
            for (my $py = 0; $py < PANELIZE->{'y'}; ++$py)
            {
                my ($xofs, $yofs, $numsubs) = (inchesX($px * ($pcbLayout{'xmax'} - $pcbLayout{'xmin'}) + $pcbLayout{'xmin'}) + PANELIZE->{'xpad'}, inchesY($py * ($pcbLayout{'ymax'} - $pcbLayout{'ymin'}) + $pcbLayout{'ymin'}) + PANELIZE->{'ypad'}, 0);
                DebugPrint(sprintf("panel[$px, $py]: xofs %5.3f, yofs %5.3f, bounding (%5.3f, %5.3f) .. (%5.3f, %5.3f)\n", $xofs, $yofs, $minX, $minY, $maxX, $maxY), 8);
                my @xylines = split /\n/, $body;
                foreach my $xyline (@xylines) #adjust all X + Y coordinates
                {
                    if ($xyline =~ m/X(-?\d+)/g)
                    {
                        my ($stofs, $enofs, $newxval) = ($-[0], $+[0], $1/10000);
                        if (($newxval < $minX) && ($px || !PANELIZE->{'overhangs'})) { $newxval = $xofs + $minX; } #trim so doesn't interfere with next panel
                        elsif (($newxval > $maxX) && (($px + 1 < PANELIZE->{'x'}) || !PANELIZE->{'overhangs'})) { $newxval = $xofs + $maxX; }
                        else { $newxval += $xofs; }
                        $newxval = sprintf("X%07.4f", $newxval);
                        $newxval =~ s/\.//;
                        $xyline = substr($xyline, 0, $stofs) . $newxval . substr($xyline, $enofs);
                        ++$numsubs;
                    }
                    if ($xyline =~ m/Y(-?\d+)/g)
                    {
                        my ($stofs, $enofs, $newyval) = ($-[0], $+[0], $1/10000);
                        if (($newyval < $minY) && ($py || !PANELIZE->{'overhangs'})) { $newyval = $yofs + $minY; } #trim so doesn't interfere with next panel
                        elsif (($newyval > $maxY) && (($py + 1 < PANELIZE->{'y'}) || !PANELIZE->{'overhangs'})) { $newyval = $yofs + $maxY; }
                        else { $newyval += $yofs; }
                        $newyval = sprintf("Y%07.4f", $newyval);
                        $newyval =~ s/\.//;
                        $xyline = substr($xyline, 0, $stofs) . $newyval . substr($xyline, $enofs);
                        ++$numsubs;
                    }
                }
                DebugPrint(sprintf("step and repeat: x $px ofs $xofs, y $py ofs $yofs, substitutions: $numsubs, panel len %d vs. %d\n", length(join("\n", @xylines)), length($body)), 16);
                $panels .= join("\n", @xylines). "\n";
                $psubs += $numsubs;
            }
        }
        DebugPrint(sprintf("panelization: overall size is now %5.3f x %5.3f, body size: %dK => %dK, X/Y adjusts: $psubs, panelization time: %.2f sec.\n", PANELIZE->{'x'} * inchesX($pcbLayout{'xmax'}), PANELIZE->{'y'} * inchesY($pcbLayout{'ymax'}), length($body)/K, length($panels)/K, time() - $ptime), 2); #Time::HiRes::gettimeofday();
        $body = $panels;
    }
    return $body;
}

# CYO - remove noise lines in copper generated layers
# parameters - $body (global)
# return value - none ($body with noise lines removed) - global
sub stripNoise
{
	my ($body) = @_;
#	my @bodylines = split /\n/, $body;
#	my $bodysize = scalar(@bodylines);
#	my $bodyindex = 0;
#	my $stripbody = "";
#    $body =~ s/%LPC\*%/G04 $&/g; #comment out subtractive polarity commands only; CAUTION: leave G54D aperture commands intact because later commands might need this aperture
    if (REMOVE_POLARITY) { $body =~ s/%LPC\*%\n//g; } #remove subtractive polarity commands only (Gerbv doesn't like commented out polarity commands); CAUTION: leave G54D aperture commands intact because later commands might need this aperture
    return $body;
#	do {
#		if (($bodylines[$bodyindex] =~ /%LPC%*/)
#		&& ($bodylines[$bodyindex+1] =~ /G54D/)
#		&& ($bodylines[$bodyindex+2] =~ /G04/))
#		{
#			$bodyindex += 3;
#		}
#		else
#		{
##			$stripbody .= join("\n", $bodylines[$bodyindex]). "\n";
#			$stripbody .= $bodylines[$bodyindex]. "\n";
#			$bodyindex += 1;
#		}
#	} while $bodyindex < $bodysize;
#	$body = $stripbody;
#	return $body;
}

#generate a suggested/possible 3-letter file extension based on file name:
#parameters: filename
#return value: filename with suggested extension
sub GerbExt
{
    my ($filename) = @_; #shift();
#    my $filename = shift();

    if ($filename =~ m/copper/i)
    {
#        if ($filename =~ m/top/i) { $filename .= "(GTL)"; }
#        elsif ($filename =~ m/bottom/i) { $filename .= "(GBL)"; }
        $filename .= ($filename =~ m/bottom/i)? "(GBL)": "(GTL)"; #assume top unless found otherwise
    }
    elsif ($filename =~ m/silk/i)
    {
        if ($filename =~ m/bottom/i) { $filename .= "(GBO)"; }
        else { $filename .= "(GTO)"; } #assume top unless found otherwise
    }
    elsif ($filename =~ m/mask/i)
    {
#        if ($filename =~ m/top/i) { $filename .= "(GTS)"; }
#        elsif ($filename =~ m/bottom/i) { $filename .= "(GBS)"; }
        $filename .= ($filename =~ m/bottom/i)? "(GBS)": "(GTS)"; #assume top unless found otherwise
    }
    elsif ($filename =~ m/outline/i)
    {
        $filename =~ s/-?(top|bottom)$//i; #applies to both top and bottom, so drop that part of name
        $filename =~ s/-?(silk|copper)$//i; #applies to both top and bottom, so drop that part of name
        $filename .= "(OLN)";
    }
    $filename .= ".grb";
    return $filename;
}

#convert from inches back to 1/72's:
#parameters: size in inches
#return value: size in points
sub points
{
    our $scaleFactor; #globals

    return shift() / $scaleFactor;
}
        
#convert 1/72's to inches:
#apply horizontal offset:
#parameters: size in points, true/false to return decimal point in string (optional, numeric if not passed)
#return value: size in inches along X axis
sub inchesX
{
    our $offsetX; #globals

    my $val = shift() + $offsetX;
    return scalar(@_)? inches($val, shift()): inches($val);
}

#UN-convert inches back to 1/72's:
#apply horizontal offset:
#parameters: size in inches along X axis
#return value: size in points
sub unInchesX
{
    our ($offsetX, $scaleFactor); #globals

    return shift();
#    return (shift() - 2 * $offsetX) * $scaleFactor;
#    return (shift() / $scaleFactor) - $offsetX;
#    return shift() - $offsetX;
#    return shift() + $offsetX / $scaleFactor;
#    return shift() - $offsetX * $scaleFactor;
}

#apply vertical offset:
#parameters: size in points, true/false to return decimal point in string (optional, numeric if not passed)
#return value: size in inches along Y axis
sub inchesY
{
    our $offsetY; #globals

    my $val = shift() + $offsetY;
    return scalar(@_)? inches($val, shift()): inches($val);
}

#UN-apply vertical offset:
#parameters: size in inches along Y axis
#return value: size in points
sub unInchesY
{
    our ($offsetY, $scaleFactor); #globals

    return shift();
#    return (shift() - 2 * $offsetY) * $scaleFactor;
#    return (shift() / $scaleFactor) - $offsetY;
#    return shift() - $offsetY;
#    return shift() + $offsetY / $scaleFactor;
#    return shift() - $offsetY * $scaleFactor;
}

#convert (X, Y) back to points:
#parameters: size in inches along X, Y axes
#return value: sizes in points
sub unInchesXY
{
    my $x = shift();
    my $y = shift();
    return (unInchesX($x), unInchesY($y));
}

#return scaled dimension as a value or string:
#parameters: size in points, true/false to return decimal point in string (optional, numeric if not passed)
#return value: size in inches
sub inches #ToInches
{
    our $scaleFactor; #globals

    # Get the number to convert
    my $input = shift(); #(@_);

    # Convert it to inches
    my $inches = $input * $scaleFactor;
    if (METRIC) { $inches *= 25.4; } #allow metric

    if (!scalar(@_)) { return $inches; } #return as float
    my $want_decpt = shift(); #optional flag to keep decimal point

    # Print it in 2.4 format
    my $text = sprintf("%07.4f", $inches);
    
    # Remove the decimal point
    if (!$want_decpt) { $text =~ s/\.//; } #dec pt optional
    
    return $text;
}


###########################################################################
#Misc helper functions:
###########################################################################

#check if a value is even:
#parameters: value to check
#return value: true/false if even
sub even
{
    return !(shift() & 1);
}

#check if a value is odd:
#parameters: value to check
#return value: true/false if odd
sub odd
{
    return shift() & 1;
}

#round a value to nearest 1/10:
#if PDF units are already 1/600, we don't need more than 1 dec place here (no need for numbers like 149.996)
sub tenths
#parameters: value to be rounded
#return value: rounded value
{
    return shift(); #just leave it as-is for now
    #use this line to round off to nearest 1/10 instead:
    #return 1 * sprintf("%.1f", shift());
}


#return base part of a file name:
#sub basename
#{
##    my ($filename) = @_;
#    my @filename = split /[\\\/]+/, shift(); #$filename;
##            my ($vol, $dir, $title) = File::Spec->splitpath($1);
##            $title =~ s/^.*[\/\\]//; #drop Windows dir on Linux and vice versa (File::Spec seems to be platform-specific)
##for my $n (@filename) { print STDERR $n, "\n"; }
#    $filename[-1] =~ s/\.[a-z]{3,4}$//i; #drop file extension
#    return $filename[-1];
#}


#show an error/warning message:
#Shows last 2 stack frame lines (for easier debug)
#parameters: warning message to display
#return value: none (uses globals)
sub mywarn
{
    our $warnings; #globals

    my ($msg) = @_; #shift();
    my ($package, $filename, $line, $sub) = caller; #(1); #info about caller
    my $from = "   @" . $line;
    ($package, $filename, $line, $sub) = caller(1); #info about calling function
    if (defined $line) { $from .= " @" . $line; }
    ($package, $filename, $line, $sub) = caller(2); #info about calling function
    if (defined $line) { $from .= " @" . $line; }
#    $msg =~ s/\n$//gs; #remove last \n and put location at end
    DebugPrint("${\(YELLOW)}WARNING[$warnings]: $msg$from${\(RESET)}\n", 0);
    ++$warnings;
}

#show debug messages only if wanted:
#Shows last 2 stack frame lines (for easier debug)
#parameters: debug message to display, debug level (used for filtering)
#return value: none (uses globals)
sub DebugPrint
{
    our $body; #globals

    my ($msg, $level) = @_;
#    if (!$level) { print STDOUT BLUE, $msg, RESET; return; } #always show this one
    my ($package, $filename, $line, $sub) = caller; #(1); #info about caller
    my $from = "   @" . $line;
    ($package, $filename, $line, $sub) = caller(1); #info about calling function
    if (defined $line) { $from .= " @" . $line; }
    $msg =~ s/\n$//gs; #remove \n at end
    $msg = uncolor($msg);

    if (WANT_DEBUG >= $level) #want this level of detail (always true for level 0)
    {
        if (($level <= 0) && (!-t STDOUT)) { print STDERR uncolor(BLUE), "$msg\n", uncolor(RESET); } #show top-level msgs on screen if stdout redirected to file
#        substr($msg, (substr($msg, -length(RESET)) == RESET)? -length(RESET): length($msg), 0) = $from; #append line# before last color change
#        substr($msg, ($msg =~ qr/${\(RESET)}$/)? -length(RESET): length($msg), 0) = $from; #append line# before last color change
#my $var = ($test1 =~ m/{\Q\(RESET)\E}$/)? TRUE: FALSE; print $var, "\n";
#$result = ($str =~ m/{\Q\(RESET)\E}$/)? TRUE: FALSE; print $result, "\n";
#        print STDOUT BLUE, $msg . "\n", RESET; #"$msg $from\n", RESET;
        substr($msg, (substr($msg, -length(RESET)) eq RESET)? -length(RESET): length($msg), 0) = $from; #append line# before last color change
        if (-t STDOUT) { print STDOUT uncolor(BLUE), $msg, "\n", uncolor(RESET); } #to screen #"$msg $from\n"
        else { print STDOUT colorstrip($msg), "\n"; } #to file
    }
    if (GERBER_DEBUG >= $level) { $msg = colorstrip($msg); $body .= "G04 $msg $from*\n"; }
}

sub uncolor
{
    my ($msg) = @_; #shift();
    return WANT_COLORS? $msg: colorstrip($msg);
}

#eof
