"use strict";
var __awaiter = (this && this.__awaiter) || function (thisArg, _arguments, P, generator) {
    function adopt(value) { return value instanceof P ? value : new P(function (resolve) { resolve(value); }); }
    return new (P || (P = Promise))(function (resolve, reject) {
        function fulfilled(value) { try { step(generator.next(value)); } catch (e) { reject(e); } }
        function rejected(value) { try { step(generator["throw"](value)); } catch (e) { reject(e); } }
        function step(result) { result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected); }
        step((generator = generator.apply(thisArg, _arguments || [])).next());
    });
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.getPublishRegistry = exports.run = void 0;
const tl = require("azure-pipelines-task-lib/task");
const constants_1 = require("./constants");
const npmregistry_1 = require("azure-pipelines-tasks-packaging-common/npm/npmregistry");
const npmtoolrunner_1 = require("./npmtoolrunner");
const util = require("azure-pipelines-tasks-packaging-common/util");
const npmutil = require("azure-pipelines-tasks-packaging-common/npm/npmutil");
function run(packagingLocation) {
    return __awaiter(this, void 0, void 0, function* () {
        const workingDir = tl.getInput(constants_1.NpmTaskInput.WorkingDir) || process.cwd();
        const npmrc = npmutil.getTempNpmrcPath();
        const npmRegistry = yield getPublishRegistry(packagingLocation);
        tl.debug(tl.loc('PublishRegistry', npmRegistry.url));
        npmutil.appendToNpmrc(npmrc, `registry=${npmRegistry.url}\n`);
        npmutil.appendToNpmrc(npmrc, `${npmRegistry.auth}\n`);
        // For publish, always override their project .npmrc
        const npm = new npmtoolrunner_1.NpmToolRunner(workingDir, npmrc, true);
        npm.line('publish');
        npm.execSync();
        tl.rmRF(npmrc);
        tl.rmRF(util.getTempPath());
    });
}
exports.run = run;
function getPublishRegistry(packagingLocation) {
    return __awaiter(this, void 0, void 0, function* () {
        let npmRegistry;
        const registryLocation = tl.getInput(constants_1.NpmTaskInput.PublishRegistry) || null;
        switch (registryLocation) {
            case constants_1.RegistryLocation.Feed:
                tl.debug(tl.loc('PublishFeed'));
                const feed = util.getProjectAndFeedIdFromInputParam(constants_1.NpmTaskInput.PublishFeed);
                npmRegistry = yield npmregistry_1.NpmRegistry.FromFeedId(packagingLocation.DefaultPackagingUri, feed.feedId, feed.projectId, false /* authOnly */, true /* useSession */);
                break;
            case constants_1.RegistryLocation.External:
                tl.debug(tl.loc('PublishExternal'));
                const endpointId = tl.getInput(constants_1.NpmTaskInput.PublishEndpoint, true);
                npmRegistry = yield npmregistry_1.NpmRegistry.FromServiceEndpoint(endpointId);
                break;
        }
        return npmRegistry;
    });
}
exports.getPublishRegistry = getPublishRegistry;
