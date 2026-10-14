# Character Physics & Mocap for Surfing Games
**Tools:** Blender, Godot 4 MCP, AI Video-to-Mocap, Claude Code

## 1. The Golden Rule: Blender vs. Godot Physics
When building a game, it is crucial to understand where physics happen:
*   **Blender's Job:** Pre-calculating bone movements (Animations/Motion Capture) and assigning bone weights (Rigging). Blender *does not* handle the real-time balancing physics of the game.
*   **Godot's Job:** Real-time physics. Godot takes the animated skeleton from Blender and applies IK (Inverse Kinematics) and Ragdoll physics to react to the wave in real-time.

## 2. Clever Motion Capture (The Video-to-3D Workflow)
You asked if giving video of a surfer to an AI would help. **Yes, absolutely.** This is the cutting-edge way to get AAA animations as a solo dev.

**The "AI Video-to-Mocap" Pipeline:**
1.  **Source the Video:** Film yourself pretending to surf, find a YouTube video of a pro surfer, OR use an AI video generator like **Kling AI, Runway Gen-3, or Sora** to generate a perfectly framed video of a surfer doing a specific trick.
2.  **Extract the 3D Bones:** Upload that 2D video to a free/freemium AI mocap tool like **Plask.ai, Rokoko Video, or DeepMotion**. These tools watch the 2D video and output a 3D skeleton animation (FBX/BVH file).
3.  **Blender Retargeting:** Import the FBX into Blender. Use a free addon like the **Rokoko Studio Live** plugin to map the extracted mocap skeleton onto your specific 3D surfer model.
4.  **Export to Godot:** Export the rigged, animated model as a `.glb` (GLTF) file into Godot.

## 3. Applying Physics to the Character in Godot
To make the surfing look real, you can't just play a static animation. The wave is moving, so the character's body must react. Claude needs to build these three systems:

*   **Inverse Kinematics (IK):** Godot's `SkeletonIK3D` node. You tell the system, "Keep the feet glued to the surfboard no matter what." As the surfboard tilts up and down on the wave, the IK system mathematically bends the character's knees and ankles dynamically to absorb the shock, just like a real surfer.
*   **Blend Spaces (`AnimationTree`):** You use Blender to create mocap animations for leaning heavily left, leaning right, crouching, and standing. Claude will write an `AnimationTree` in Godot that blends these animations smoothly based on the player's joystick input.
*   **Active Ragdoll (Wipeouts):** When the player crashes, Godot switches the skeleton from "Animation Mode" to "Physics Mode." Godot uses `PhysicalBone3D` nodes to turn the character into a physics ragdoll that tumbles through the water realistically.

## 4. What to Download vs. What to Build from Scratch

**What to Download (Don't reinvent the wheel):**
*   **Mixamo.com:** Download basic humanoid meshes and generic animations (idle breathing, paddling).
*   **Blender Addon - "Rigify":** Built into Blender. Use it to instantly create a game-ready skeleton with proper joint limits.
*   **Plask.ai/DeepMotion:** For extracting surfing-specific mocap.

**Proof of Concepts (PoCs) to Build from Scratch (With Claude):**
*   **PoC 1 - The IK Foot Anchor:** A blank scene with just a surfboard and a rigged dummy. The goal: Rotate the surfboard via script and ensure the dummy's knees bend to keep its feet perfectly flat on the board.
*   **PoC 2 - The Wipeout Trigger:** A scene where the character is playing a surfing animation, and upon pressing a button, immediately transitions into a `PhysicalBone3D` ragdoll simulation and falls off the board.

---

## 5. The "Level 3" Prompt for Claude Code (Animation & Physics)
**Copy this block and provide it to Claude Code for character controller implementation:**

***

`<system_prompt_addition>`
**Subject:** Advanced Character Physics, Animation Blending, and IK for Surfing.

**Core Directives for Surfer Implementation:**
1.  **Skeleton & IK:** The player character will use a `Skeleton3D`. You must implement `SkeletonIK3D` (or equivalent Godot 4 IK logic) for the character's legs. The feet (targets) must remain locked to specific `Marker3D` nodes on the surfboard, forcing the knees to bend dynamically as the board tilts on the procedural wave mesh.
2.  **AnimationTree Setup:** Do not hard-code animation playback. Generate a script to control an `AnimationTree` using a `BlendSpace2D`. The X-axis will represent turning/leaning (left/right), and the Y-axis will represent stance (crouching/carving vs. standing upright). 
3.  **Active Ragdoll (Wipeout State):** Generate the `PhysicalBone3D` setup script. When the `wipeout()` function is called, the script must disable the `AnimationTree`, start physical bone simulation for ragdoll effects, and detach the player's `RigidBody3D` momentum from the surfboard to let them fall into the water.
4.  **Mocap Pipeline Awareness:** Assume all animations (`.glb` files) are imported motion capture data. Do not attempt to procedurally animate the spine or arms via code; rely on blending the mocap clips, using IK *only* for foot placement and board tracking.
`</system_prompt_addition>`