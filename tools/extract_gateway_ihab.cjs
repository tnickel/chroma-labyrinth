// Rebuild the surface-habitat source asset from NASA's Gateway Core.glb.
// Install @gltf-transform/{core,extensions,functions}@4.5.1 in a separate
// directory, put its node_modules on NODE_PATH, and run:
//   node tools/extract_gateway_ihab.cjs <Gateway Core.glb> <gateway_ihab.glb>
// Only the iHAB subtree is retained. Its large orbital radiator and the six
// deployable NDS shutters/hinges are omitted for the surface installation.
const { NodeIO } = require('@gltf-transform/core');
const { ALL_EXTENSIONS } = require('@gltf-transform/extensions');
const { prune } = require('@gltf-transform/functions');

async function main() {
  const [, , source, destination] = process.argv;
  if (!source || !destination) {
    throw new Error('Usage: node extract_gateway_ihab.cjs <Gateway Core.glb> <gateway_ihab.glb>');
  }
  const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
  const doc = await io.read(source);
  const scenes = doc.getRoot().listScenes();
  const mover = scenes[0]?.listChildren().find((node) => node.getName() === 'mover');
  const habitat = mover?.listChildren().find((node) => node.getName() === 'iHAB');
  if (!mover || !habitat) throw new Error('NASA Gateway iHAB node hierarchy not found.');

  for (const node of mover.listChildren()) {
    if (node !== habitat) node.dispose();
  }
  habitat.setTranslation([0, 0, 0]);
  mover.setRotation([0, 0, 0, 1]);
  doc.getRoot().listNodes()
    .filter((node) => node.getName() === 'I-Hab Radiator' || node.getName().startsWith('NDS Shutter'))
    .forEach((node) => node.dispose());

  // Discard orphaned descendants of the removed branches before pruning
  // their geometry and textures. Shared iHAB docking-port meshes are retained.
  const reachable = new Set();
  function visit(node) {
    if (reachable.has(node)) return;
    reachable.add(node);
    node.listChildren().forEach(visit);
  }
  scenes.forEach((scene) => scene.listChildren().forEach(visit));
  doc.getRoot().listNodes().filter((node) => !reachable.has(node)).forEach((node) => node.dispose());
  await doc.transform(prune());
  await io.write(destination, doc);
  console.log(`Wrote ${destination}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
