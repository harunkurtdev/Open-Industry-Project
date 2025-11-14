# Spiral Belt Conveyor

## Overview

The Spiral Belt Conveyor is a helix/spiral structure that moves items vertically while also conveying them horizontally. This type of conveyor is commonly used in industrial settings for elevation changes in production lines, warehouses, and manufacturing facilities.

## Features

- **Configurable geometry**: Adjust inner radius, conveyor width, height per revolution, and number of revolutions
- **Customizable appearance**: Set belt color and texture patterns
- **Physics support**: Configure friction and other physical properties via physics materials
- **PLC integration**: Communicate with PLCs and OPC UA servers using standard industrial protocols
- **Procedural mesh generation**: The spiral path is generated procedurally based on parameters

## Parameters

### Geometric Parameters

- **Inner Radius** (default: 1.0m, min: 0.5m): The radius of the inner edge of the spiral conveyor
- **Conveyor Width** (default: 1.524m, min: 0.3m): The width of the conveyor belt from inner to outer edge
- **Height Per Revolution** (default: 2.0m, min: 0.5m): The vertical distance gained for each complete turn of the spiral
- **Number of Revolutions** (default: 1.0, range: 0.25-4.0): How many complete turns the spiral makes

### Appearance Parameters

- **Belt Color**: RGB color of the conveyor belt (default: white)
- **Belt Texture**: Choose between STANDARD and ALTERNATE texture patterns

### Operation Parameters

- **Speed** (default: 2.0 m/s): The linear speed of the conveyor belt
- **Belt Physics Material**: Custom physics material for friction and bounce properties

### Communications Parameters

- **Enable Comms**: Enable/disable PLC communication
- **Speed Tag Group Name**: Tag group for speed control
- **Speed Tag Name**: Tag name for reading/writing speed values
- **Running Tag Group Name**: Tag group for running status
- **Running Tag Name**: Tag name for running state (on/off)

## Usage

### Adding to a Scene

1. Open the Godot editor with your Open Industry Project
2. Navigate to the Parts tab
3. Find **SpiralBeltConveyor** or **SpiralBeltConveyorAssembly**
4. Drag it into your simulation scene
5. Adjust the parameters in the Inspector panel

### Configuring Size

The spiral conveyor's size is automatically calculated from:
- Inner radius + conveyor width determines the diameter
- Height per revolution × number of revolutions determines the total height

### Integration with PLC/OPC UA

The spiral conveyor supports the same communication features as other conveyors:

1. Enable communications in the Comms panel
2. Set up your tag groups (OPC UA, Ethernet/IP, or Modbus TCP)
3. Configure the speed and running tag names in the conveyor properties
4. The conveyor will read speed values and write running status to your PLC/OPC server

## Technical Details

### Implementation

The spiral conveyor is implemented in:
- \`src/Conveyor/spiral_belt_conveyor.gd\` - Core conveyor logic
- \`src/ConveyorAssembly/spiral_belt_conveyor_assembly.gd\` - Assembly wrapper
- \`parts/SpiralBeltConveyor.tscn\` - Scene definition
- \`parts/assemblies/SpiralBeltConveyorAssembly.tscn\` - Assembly scene

### Mesh Generation

The conveyor mesh is generated procedurally using a parametric helix equation:
\`\`\`
x = r * cos(θ)
y = h * θ / (2π)
z = r * sin(θ)
\`\`\`

Where:
- r is the radius (varies between inner_radius and inner_radius + conveyor_width)
- θ is the angle parameter (0 to num_revolutions × 2π)
- h is height_per_revolution

The mesh includes:
- Top and bottom surfaces for the belt
- Inner and outer side walls
- Procedural collision shape for physics simulation

## Examples

### Simple Single-Turn Spiral
\`\`\`
Inner Radius: 1.0m
Conveyor Width: 1.5m
Height Per Revolution: 2.0m
Number of Revolutions: 1.0
\`\`\`
Creates a spiral that completes one turn and rises 2 meters.

### Compact Multi-Turn Spiral
\`\`\`
Inner Radius: 0.5m
Conveyor Width: 1.0m
Height Per Revolution: 1.5m
Number of Revolutions: 3.0
\`\`\`
Creates a tighter spiral with three complete turns, gaining 4.5 meters in height.

### Wide Gentle Incline
\`\`\`
Inner Radius: 2.0m
Conveyor Width: 2.0m
Height Per Revolution: 3.0m
Number of Revolutions: 0.5
\`\`\`
Creates a gentle half-turn spiral with a large diameter, rising 1.5 meters.

## See Also

- Belt Conveyor
- Curved Belt Conveyor
- Roller Conveyor
- OIPComms Communication System
