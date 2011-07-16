#!/usr/bin/perl
#
# pdf2gerb 1.4
#
# (c) 2010 Matthew M. Swann
#          swannman@mac.com
#
# More information about this work can be found at the following URL:
# http://swannman.wordpress.com/projects/pdf2gerb/
#
# This work is released under the terms and conditions set forth under
# the GNU General Public License 3.0.  For more details, see the following:
# http://www.gnu.org/licenses/gpl-3.0.txt
#
###########################################################################
use Cwd;

sub ToInches;
sub ToDrillInches;
sub GetAperture;
sub GetDrillAperture;
sub ComputeBezier;

# Set this to 1 if you need TurboCAD support.
$turboCAD;

# Used by GetAperture as well as the main routine to store aperture defn's
@apertures = ();

# Used by GetDrillAperture
@drillApertures = ();

# Used by the main routine to store layer names
@layerTitles = ();

# Multiply value in points by this to get value in inches
$scaleFactor = 0.0138888889;

# The precision used when computing a bezier curve. Higher numbers are more precise but slower.
$bezierPrecision = 100;

# The max number of characters to read into memory
$maxBytes = 5 * 1024 * 1024; # 5 MB

if (@ARGV != 1)
{
    print "usage: pdf2gerb <pdf file>\n\n";
    exit;
}

# Get the file path from the command line
$pdfFilePath = $ARGV[0];

# Calculate the output dir from the input file path
$pdfFilePath =~ /^(.+)\/.+$/;

# Quick hack to handle cwd is same dir as output dir
if ($1 eq "") 
{
   $outputDir = cwd() . "/";
}
else
{
   $outputDir = $1 . "/";
}

# Open the file for reading
open pdfFile, "< $pdfFilePath";

# Read in up to MAXBYTES
read(pdfFile, $rawPdfContents, $maxBytes);

# Fix a problem where content lines end in \r (0x0D) and are unprintable
@rawLines = split /(\r\n|\n\r|\n|\r)/, $rawPdfContents;
chomp(@rawLines);
$pdfContents = join("\n", @rawLines);
$pdfContents =~ s/\r//gs;
$pdfContents =~ s/\n\n/\n/gs;

# Get the layer titles
while ($pdfContents =~ /\/Title\((.+?)\)/gs) {
#print "title: $1\n";
    push(@layerTitles, $1);
}

# Which layer we're on
$currentLayer = 0;

# Does BDC occur in this file?  (It will not if the file is a single layer)
if ($pdfContents !~ /BDC/gs) {
    # No, so -- as a hack -- let's convert "stream" -> "BDC" and "endstream" -> "EMC"
    $pdfContents =~ s/endstream/EMC/gs;
    $pdfContents =~ s/stream/BDC/gs;
    
    # Make up a layer title if the array is empty
    if (scalar(@layerTitles) == 0) {
        push(@layerTitles, "pdf2gerb_output");
    }
}

# Reset the match position to the beginning
pos($pdfContents) = 0;

# Break the file into layers (BDC...EMC)
while ($pdfContents =~ /BDC(.*?)EMC/gs) {

    # Break the layer into separate lines
    @lines = split /\n/, $1;
    
    # Flags and variables
    $prevLine;
    $startPositionX;
    $startPositionY;
    $circleMinX = 0;
    $circleMaxX = 0;
    $circleMinY = 0;
    $circleMaxY = 0;
    $circleSegNum = 0;
    $rectWaiting = 0;
    $lastAperture;
    $lastStrokeWeight = 0;
    $visibleFillColor = 1;
    $currentDrillAperture = "";
    $offsetX = 0;
    $offsetY = 0;
    $currentX = 0;
    $currentY = 0;
    @circlePaths = ();
    
    $header = "";
    $body = "";    # start off drawing straight lines
    
    $drillHeader = "%\nM48\nM72\n";
    $drillBody = "";
    
    # Default to 1pt stroke weight
    $lastStrokeWeight = 1;
    $lastAperture = GetAperture(1);
    $body = $body . "G54" . $lastAperture . "*\n";
    
    foreach $line (@lines) {
        if ($line =~ /1 0 0 1 (-?\d+.?\d*\s)(-?\d+.?\d*\s)cm$/) {
            # Lines ending in cm define a transformation matrix...
            # 1 0 0 1 X Y means offset all values by X and Y.
            $offsetX = $1;
            $offsetY = $2;
            #print "offset:" . $1 . " " . $2 . "\n";
            next;
        }
        
        if ($line =~ /(-?\d+.?\d*\s)(-?\d+.?\d*\s)(-?\d+.?\d*\s)(-?\d+.?\d*\s)re$/) {
            # Lines ending in re define a rectangle, often followed
            # by W n to define the clipping rect
            $rectWaiting = 1;
            $prevLine = $line;
            #print "rect:" . $1 . " " . $2 . " " . $3 . " " . $4 . "\n";
            next;
        }
        
        if ($line =~ /^W n$/) {
            # W n makes the prev re command set the clipping rect
            if ($rectWaiting == 1) {
                # Use the previous line
                $rectWaiting = 0;
                ;
            }
            else {
                # There wasn't a previously-defined rect... ?!
                print "Error: clipping mask def'n without rect\n";
            }
            
            next;
        }
        
        if ($rectWaiting == 1) {
            # We didn't use the previously-defined rect to set a clipping
            # mask, so treat it as a drawable path.  First, reparse the rectangle def'n
            $prevLine =~ /(-?\d+.?\d*\s)(-?\d+.?\d*\s)(-?\d+.?\d*\s)(-?\d+.?\d*\s)re$/;
            
            # Move to the top-left corner as specified by the re command
            $body = $body . "X" . ToInches($1 + $offsetX) . "Y" . ToInches($2 + $offsetY) . "D02*\n";
            
            # Draw a line to the top-right corner
            $body = $body . "X" . ToInches($1 + $offsetX + $3) . "Y" . ToInches($2 + $offsetY) . "D01*\n";
            
            # Draw a line to the bottom-right corner
            $body = $body . "X" . ToInches($1 + $offsetX + $3) . "Y" . ToInches($2 + $offsetY + $4) . "D01*\n";
            
            # Draw a line to the bottom-left corner
            $body = $body . "X" . ToInches($1 + $offsetX) . "Y" . ToInches($2 + $offsetY + $4) . "D01*\n";
            
            # Draw a line back to the top-left corner
            $body = $body . "X" . ToInches($1 + $offsetX) . "Y" . ToInches($2 + $offsetY) . "D01*\n";
            
            $rectWaiting = 0;
            
            #print "@layerTitles[$currentLayer]  rectangle\n";
            next;
        }
        
        if ($line =~ /^f$/) {
            # f means fill what we just drew - generally a circle
            ComputeCircle();

            # Is this a visible circle?
            if ($visibleFillColor == 0) {
                #print "drill circle: $circleMinX $circleMaxX $circleMinY $circleMaxY\n";
            
                # It's a drill hole, so get the drill aperture
                $thisAperture = GetDrillAperture($diameter);
                
                # If we're not currently on this aperture, write out a tool command
                if ($thisAperture ne $currentDrillAperture) {
                    $drillBody = $drillBody . $thisAperture . "\n";
                    $currentDrillAperture = $thisAperture;
                }
                
                # Write the coordinates
                $drillBody = $drillBody . "X" . ToDrillInches($centerX + $offsetX) . "Y" . ToDrillInches($centerY + $offsetY) . "\n";
            }
            else {
                # It's a visible, filled circle Ñ eg a pad
                #print "circle fill: X($centerX) Y($centerY)\n";
                $body = $body . "G54" . GetAperture($diameter) . "*\n";
                $body = $body . "X" . ToInches($centerX + $offsetX) . "Y" . ToInches($centerY + $offsetY) . "D03*\n";
                $body = $body . "G54" . $lastAperture . "*\n";
            }
            
            # Clear the circle stack
            @circlePaths = ();

            next;
        }
        
        if ($turboCAD && ($line =~ /^S$/)) {
            # S means stroke what we just drew - only supported for circles
            # as a workaround for TurboCAD, which can't fill circles (!)
            # Is there a circle waiting?
            ComputeCircle();
                
            # First, compute the drill diameter
            #print "circle stroke ($diameter) ($lastStrokeWeight)\n";
            $thisAperture = GetDrillAperture($diameter - $lastStrokeWeight);
            
            # If we're not currently on this aperture, write out a tool command
            if ($thisAperture ne $currentDrillAperture) {
                $drillBody = $drillBody . $thisAperture . "\n";
                $currentDrillAperture = $thisAperture;
            }
            
            # Write the coordinates
            $drillBody = $drillBody . "X" . ToDrillInches($centerX + $offsetX) . "Y" . ToDrillInches($centerY + $offsetY) . "\n";

            # Next, draw the actual circle
            $body = $body . "G54" . GetAperture($diameter + $lastStrokeWeight) . "*\n";
            $body = $body . "X" . ToInches($centerX + $offsetX) . "Y" . ToInches($centerY + $offsetY) . "D03*\n";
            $body = $body . "G54" . $lastAperture . "*\n";
            
            
            # Clear the circle stack
            @circlePaths = ();
            
            next;
        }
        
        if ($line =~ /(-?\d+.?\d*)\sw/) {
            # Number followed by w is a stroke weight
            #print "weight:" . $1 . "\n";
            $lastStrokeWeight = $1;
            $lastAperture = GetAperture($1);
            $body = $body . "G54" . $lastAperture . "*\n";
            next;
        }
        
        if ($line =~ /(-?\d+.?\d*\s)(-?\d+.?\d*\s)(-?\d+.?\d*\s)rg$/) {
            # Three numbers followed by rg define the current fill color in RGB
            # We want to ignore anything drawn in white
            if (($1 == 1) && ($2 == 1) && ($3 == 1)) {
                # This changes color to white, which makes things invisible
                $visibleFillColor = 0;
            }
            else {
                $visibleFillColor = 1;
            }
            #print "fill color:" . $1 . " " . $2 . " " . $3 . "\n";
            next;
        }
        
        if ($line =~ /(-?\d+.?\d*\s)(-?\d+.?\d*\s)(-?\d+.?\d*\s)(-?\d+.?\d*\s)k$/) {
            # Four numbers followed by k define the current fill color in CMYK
            # We want to ignore anything drawn in white
            if (($1 == 0) && ($2 == 0) && ($3 == 0) && ($4 == 0)) {
                # This changes color to white, which makes things invisible
                $visibleFillColor = 0;
            }
            else {
                $visibleFillColor = 1;
            }
            #print "fill color:" . $1 . " " . $2 . " " . $3 . "\n";
            next;
        }
        
        if ($line =~ /(-?\d+.?\d*\s)(-?\d+.?\d*\s)m$/) {
            # Lines ending in m mean move to a position, which can be used
            # to close a path later on
            $startPositionX = $1;
            $startPositionY = $2;
            #print "move:" . $1 . " " . $2 . "\n";
            $body = $body . "X" . ToInches($1 + $offsetX) . "Y" . ToInches($2 + $offsetY) . "D02*\n";
            $currentX = $1;
            $currentY = $2;
            next;
        }
        
        if ($line =~ /(-?\d+.?\d*\s)(-?\d+.?\d*\s)l$/) {
            # Lines ending in l mean draw a straight line to this position
            #print "@layerTitles[$currentLayer]  line:" . $1 . " " . $2 . "\n";
            #print $line . "\n";
            $body = $body . "X" . ToInches($1 + $offsetX) . "Y" . ToInches($2 + $offsetY) . "D01*\n";
            $currentX = $1;
            $currentY = $2;
            next;
        }
        
        if ($line =~ /(-?\d+.?\d*\s)(-?\d+.?\d*\s)(-?\d+.?\d*\s)(-?\d+.?\d*\s)[v]$/) {
            # Lines ending in v mean draw a bezier curve (x2 y2 x3 y3)
            ComputeBezier("v", $1, $2, $3, $4);
            next;
        }
        
        if ($line =~ /(-?\d+.?\d*\s)(-?\d+.?\d*\s)(-?\d+.?\d*\s)(-?\d+.?\d*\s)[y]$/) {
            # Lines ending in y mean draw a bezier curve (x1 y1 x3 y3)
            ComputeBezier("y", $1, $2, $3, $4);
            next;
        }
        
        if ($line =~ /(-?\d+.?\d*\s)(-?\d+.?\d*\s)(-?\d+.?\d*\s)(-?\d+.?\d*\s)(-?\d+.?\d*\s)(-?\d+.?\d*\s)c$/) {
            # Lines ending in c mean draw a bezier path to this point (x1 y1 x2 y2 x3 y3)
            #ComputeBezier("c", $1, $2, $3, $4, $5, $6);
            
            # This might be part of a drill circle, so push it onto our stack
            # for later use in a fill statement
            push(@circlePaths, $5);
            push(@circlePaths, $6);
            next;
        }
        
        if ($line =~ /^h$/) {
            # h means draw a straight line back to the first point
            #print "close back to:" . $startPositionX . " " . $startPositionY . "\n";
            $body = $body . "X" . ToInches($startPositionX + $offsetX) . "Y" . ToInches($startPositionY + $offsetY) . "D01*\n";
            $currentX = $startPositionX;
            $currentY = $startPositionY;
            next;
        }
    }
    
    if ($body ne "") {    
        # Leading zero suppression, absolute coordinates, format=2.4
        # (Seems like this should be NO zero suppression, but doesn't validate
        # correctly otherwise.)
        $header = $header . "%FSLAX24Y24*%\n";
        
        # Measurements are in inches
        $header = $header . "%MOIN*%\n";
        
        my $i = 0;
        for ($i = 0; $i < scalar(@apertures); $i++) {
            $header = $header . "%ADD" . ($i + 10) . "C," . @apertures[$i] . "*%\n";
        }
        
        # Write this out to a file
        open outputFile, ">$outputDir@layerTitles[$currentLayer].grb";
        print outputFile $header . "G01*\n" . $body . "M02*";
        close outputFile;
    }
    
    if ($drillBody ne "") {
        # Write the drill header, format=2.3
        my $i = 0;
        for ($i = 0; $i < scalar(@drillApertures); $i++) {
            $drillHeader = $drillHeader . "T" . sprintf("%02u", ($i + 1)) . "C" . @drillApertures[$i] . "\n";
        }
        
        $drillHeader = $drillHeader . "%\n";
        $drillBody = $drillBody . "T00\nM30";
        open outputFile, ">$outputDir@layerTitles[$currentLayer].drd";
        print outputFile $drillHeader . $drillBody;
        close outputFile;
    }
    
    # Increment our layer counter
    $currentLayer = $currentLayer + 1;
    
    #print $header . $body . "M02*\n";
}

sub ToInches {
    # Get the number to convert
    my $input = shift(@_);
    
    # Convert it to inches
    $inches = $input * $scaleFactor;
    
    # Print it in 2.4 format
    $text = sprintf("%07.4f", $inches);
    
    # Remove the decimal point
    $text =~ s/\.//;
    
    return $text;
}

sub ToDrillInches {
    # Get the number to convert
    my $input = shift(@_);
    
    # Convert it to inches
    $inches = $input * $scaleFactor;
    
    # Print it in 2.3 format
    $text = sprintf("%.3f", $inches);
    
    # Remove the decimal point
    #$text =~ s/\.//;
    
    return $text;
}

sub GetAperture {  
    # Get the number to convert
    my $input = shift(@_);
    
    # Convert it to inches - but not the wacky format
    $inches = sprintf("%5.5f", ($input * $scaleFactor));

    # Look through all previously defined apertures to find the one we want
    my $i = 0;
    for ($i = 0; $i < scalar(@apertures); $i++) {
        if (@apertures[$i] eq $inches) {
            last;
        }
    }
    
    if ($i == scalar(@apertures)) {
        # We ran off the end of the array, so the aperture wasn't found
        push(@apertures, $inches);
    }
    else {
        # $i contains the index of the aperture - it was previously used
        ;
    }
    
    return "D" . ($i + 10);
}

sub GetDrillAperture {  
    # Get the number to convert
    my $input = shift(@_);
    
    # Convert it to inches - but not the wacky format
    $inches = sprintf("%4.3f", ($input * $scaleFactor));

    # Look through all previously defined apertures to find the one we want
    my $i = 0;
    for ($i = 0; $i < scalar(@drillApertures); $i++) {
        if (@drillApertures[$i] eq $inches) {
            last;
        }
    }
    
    if ($i == scalar(@drillApertures)) {
        # We ran off the end of the array, so the aperture wasn't found
        push(@drillApertures, $inches);
    }
    else {
        # $i contains the index of the aperture - it was previously used
        ;
    }
    
    return "T" . sprintf("%02u", ($i + 1));
}

sub ComputeBezier {
    # Get the type of bezier curve
    my $type = shift(@_);
    
    #print "bezier curve $type\n";
    
    # Zero out the parameters that aren't passed-in
    my $x1 = 0;
    my $y1 = 0;
    my $x2 = 0;
    my $y2 = 0;
    my $x3 = 0;
    my $y3 = 0;
    
    # Load our passed-in parameters appropriately
    if ($type eq "c")
    {
        # x1 y1 x2 y2 x3 y3
        # The curve extends from the current point to the point (x3, y3), 
        # using (x1, y1) and (x2, y2) as the Bezier control points.
        # The new current point is (x3, y3).
        $x1 = shift(@_);
        $y1 = shift(@_);
        $x2 = shift(@_);
        $y2 = shift(@_);
        $x3 = shift(@_);
        $y3 = shift(@_);
    }
    elsif ($type eq "v")
    {
        # x2 y2 x3 y3.
        # The curve extends from the current point to the point (x3, y3),
        # using the current point and (x2, y2) as the Bezier control points.
        # The new current point is (x3, y3).
        $x1 = $currentX;
        $y1 = $currentY;
        $x2 = shift(@_);
        $y2 = shift(@_);
        $x3 = shift(@_);
        $y3 = shift(@_);
    }
    elsif ($type eq "y")
    {
        # x1 y1 x3 y3.
        # The curve extends from the current point to the point (x3, y3), 
        # using (x1, y1) and (x3, y3) as the Bezier control points.
        # The new current point is (x3, y3).
        $x1 = shift(@_);
        $y1 = shift(@_);
        $x2 = shift(@_);
        $y2 = shift(@_);
        $x3 = $x2;
        $y3 = $y2;
    }
    
    # R(t) = (1Ðt)^3*P0+3t(1Ðt)^2*P1+3t^2(1Ðt)P2+t^3P3 where t -> 0 .. 1.0
    for (my $t = 0; $t <= 1.0; $t += 1/$bezierPrecision)
    {
        # Compute the new X and Y locations
        my $x = (1-$t)**3*$currentX+3*$t*(1-$t)**2*$x1+3*$t**2*(1-$t)*$x2+$t**3*$x3;
        my $y = (1-$t)**3*$currentY+3*$t*(1-$t)**2*$y1+3*$t**2*(1-$t)*$y2+$t**3*$y3;
        
        # Draw this segment of the curve
        $body = $body . "X" . ToInches($x + $offsetX) . "Y" . ToInches($y + $offsetY) . "D01*\n";
    }
    
    $currentX = $x3;
    $currentY = $y3;
}

# NOTE: modifies global variables
sub ComputeCircle {
    # Pop off the last four circle segments
    $circleMinY = pop(@circlePaths);
    $circleMaxY = $circleMinY;
    $circleMinX = pop(@circlePaths);
    $circleMaxX = $circleMinX;
    
    $currentY = $circleMinY;
    $currentX = $circleMinX;
    
    for ($i = 0; $i < 3; $i++) {
        $thisY = pop(@circlePaths);
        $thisX = pop(@circlePaths);
        
        if ($thisY > $circleMaxY)
        {
            $circleMaxY = $thisY;
        }
        if ($thisY < $circleMinY)
        {
            $circleMinY = $thisY;
        }
        if ($thisX > $circleMaxX)
        {
            $circleMaxX = $thisX;
        }
        if ($thisX < $circleMinX)
        {
            $circleMinX = $thisX;
        }
    }
    
    # Compute the aperture
    # Note that we assume a perfect circle, so we only have to look at the Y dimension.
    $diameter = $circleMaxY - $circleMinY;
    
    # Find the center of the circle
    $centerX = $circleMinX + ($diameter / 2.0);
    $centerY = $circleMinY + ($diameter / 2.0);
}
