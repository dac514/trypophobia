# Trypophobia - AI Coding Assistant Instructions

## Project Overview
Trypophobia is a Connect-4-style puzzle game built in Godot 4.5 with a unique twist: the board rotates randomly after each turn. Players must get four eyeballs in a row to win, but rotations change the game state dynamically.

## Key Architecture

### Core Game Flow
- **Main Scene** (`scenes/main.gd`): Central coordinator handling player input, turn management, and UI state
- **Board System** (`scenes/board.gd`): Manages 6x6 grid state, chip placement, and win detection
- **Board Rotator** (`scenes/board_rotator.gd`): Handles random board rotations with weighted probability system
- **Chip System**: Abstract base class (`scenes/chip.gd`) with concrete implementations for EYE, BOMB, PACMAN types

### Special Mechanics
- **Rotation Preview**: Next 3 rotations shown via `scenes/next_moves.gd` with animated icons
- **Special Chips**: BOMB destroys adjacent chips, PACMAN destroys facing chips with directional rotation
- **Physics Integration**: Uses Godot's RigidBody2D for realistic chip dropping and settling detection

### AI Bot System
Located in `utils/bot/`, implements minimax algorithm with alpha-beta pruning:
- **BotWorker** (`bot_worker.gd`): Threaded minimax search with 5-second time limit and dynamic depth
- **BotBoard** (`bot_board.gd`): Lightweight board simulation for AI move evaluation
- **BotMove** (`bot_move.gd`): Encapsulates move data including special chip directions

## Development Patterns

### Scene Structure
- Scenes are self-contained with dedicated GDScript classes
- Use `@onready` for node references and signals for loose coupling
- UI elements accessed via unique name paths (e.g., `%UI/PlayerLabel`)

### State Management
- **Globals** (`utils/globals.gd`) contains game-wide enums and info text
- Player state tracked in `main.gd` with chip inventory system
- Board state maintained as 2D array in `board.gd`

### Threading & Performance
- AI calculations run on separate thread via `BotWorker.start()`
- Physics settling detected using `ChipWatcher` utility for async coordination
- Animation systems use Godot's Tween for smooth transitions

### Asset Organization
- Sprites in `assets/` with corresponding `.import` files for Godot processing
- Shaders for visual effects: `blur.gdshader`, `fireworks.gdshader`, `highlight.gdshader`
- Fonts specifically include `NotoColorEmoji-Regular.ttf` for emoji support

## Testing & Debugging
- Use Godot's built-in debugger and scene dock for real-time inspection
- Board state can be printed via `_print_ascii_grid()` method in `board.gd`
- Bot thinking logged to console with move evaluation details

## Mobile Considerations
- Touch input detection in `main.gd` via `_is_mobile_device()`
- Button controls (T/R keys) for toggling special chip types and features
- Responsive UI scaling handled through Godot's scene system

## Key Files to Understand First
1. `scenes/main.gd` - Game coordinator and entry point
2. `utils/globals.gd` - Shared enums and constants
3. `scenes/board.gd` - Core game logic and win detection
4. `utils/bot/bot_worker.gd` - AI algorithm implementation