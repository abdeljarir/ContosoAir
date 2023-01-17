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
const path = require("path");
const tl = require("azure-pipelines-task-lib/task");
const constants_1 = require("./constants");
const npmCustom = require("./npmcustom");
const npmPublish = require("./npmpublish");
const telemetry = require("azure-pipelines-tasks-utility-common/telemetry");
const util = require("azure-pipelines-tasks-packaging-common/util");
const pkgLocationUtils = require("azure-pipelines-tasks-packaging-common/locationUtilities");
function main() {
    return __awaiter(this, void 0, void 0, function* () {
        tl.setResourcePath(path.join(__dirname, 'task.json'));
        let packagingLocation;
        try {
            packagingLocation = yield pkgLocationUtils.getPackagingUris(pkgLocationUtils.ProtocolType.Npm);
        }
        catch (error) {
            tl.debug('Unable to get packaging URIs');
            util.logError(error);
            throw error;
        }
        const forcedUrl = tl.getVariable('Npm.PackagingCollectionUrl');
        if (forcedUrl) {
            packagingLocation.DefaultPackagingUri = forcedUrl;
            packagingLocation.PackagingUris.push(forcedUrl);
        }
        yield _logNpmStartupVariables(packagingLocation);
        const command = tl.getInput(constants_1.NpmTaskInput.Command) || null;
        switch (command) {
            case constants_1.NpmCommand.Install:
                return npmCustom.run(packagingLocation, constants_1.NpmCommand.Install);
            case constants_1.NpmCommand.ContinuousIntegration:
                return npmCustom.run(packagingLocation, constants_1.NpmCommand.ContinuousIntegration);
            case constants_1.NpmCommand.Publish:
                return npmPublish.run(packagingLocation);
            case constants_1.NpmCommand.Custom:
                return npmCustom.run(packagingLocation);
            default:
                tl.setResult(tl.TaskResult.Failed, tl.loc('UnknownCommand', command));
                return;
        }
    });
}
function _logNpmStartupVariables(packagingLocation) {
    return __awaiter(this, void 0, void 0, function* () {
        try {
            // Log the NPM version
            let version;
            try {
                const syncResult = tl.execSync('npm', '--version');
                if (syncResult.stdout) {
                    version = syncResult.stdout.trim();
                }
            }
            catch (err) {
                tl.debug(`Unable to get NPM config info. Err:( ${err} )`);
            }
            // Log the NPM registries
            const command = tl.getInput(constants_1.NpmTaskInput.Command) || null;
            let npmRegistriesAry;
            const registryUrlAry = [];
            switch (command) {
                case constants_1.NpmCommand.Install:
                case constants_1.NpmCommand.Custom:
                    npmRegistriesAry = yield npmCustom.getCustomRegistries(packagingLocation);
                    break;
                case constants_1.NpmCommand.Publish:
                    npmRegistriesAry = [yield npmPublish.getPublishRegistry(packagingLocation)];
                    break;
            }
            for (const registry of npmRegistriesAry) {
                registryUrlAry.push(registry.url);
            }
            const npmTelem = {
                'command': command,
                'verbose': tl.getInput(constants_1.NpmTaskInput.Verbose) || null,
                'customRegistry': tl.getInput(constants_1.NpmTaskInput.CustomRegistry) || null,
                'customFeed': tl.getInput(constants_1.NpmTaskInput.CustomFeed) || null,
                'customEndpoint': tl.getInput(constants_1.NpmTaskInput.CustomEndpoint) || null,
                'publishRegistry': tl.getInput(constants_1.NpmTaskInput.PublishRegistry) || null,
                'publishFeed': tl.getInput(constants_1.NpmTaskInput.PublishFeed) || null,
                'publishEndpoint': tl.getInput(constants_1.NpmTaskInput.PublishEndpoint) || null,
                'npmVersion': version,
                'registries': registryUrlAry
            };
            telemetry.emitTelemetry('Packaging', 'npm', npmTelem);
        }
        catch (err) {
            tl.debug(`Unable to log NPM task telemetry. Err:( ${err} )`);
        }
    });
}
main().catch(error => {
    tl.rmRF(util.getTempPath());
    tl.setResult(tl.TaskResult.Failed, error);
});
